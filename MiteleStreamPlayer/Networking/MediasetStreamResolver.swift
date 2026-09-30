import Foundation

protocol StreamResolving: Sendable {
    func resolve(
        _ request: PlaybackRequest,
        progress: @escaping @Sendable (PreparationPhase) async -> Void
    ) async throws -> ResolvedStream
}

actor MediasetStreamResolver: StreamResolving {
    private let client: HTTPClient
    private let credentials: any CredentialProviding
    private let identityService: GigyaIdentityService
    private let atresPlayer: any AtresPlayerFetching
    /// Cached anonymous IDM login (`sid`+`beToken`) used by the FairPlay/Widevine entitlement
    /// chain — reused across plays within its JWT lifetime; no user session involved.
    private var cachedAnonymousLogin: (sid: String, beToken: String, expiry: Date)?

    init(
        client: HTTPClient,
        credentials: any CredentialProviding,
        identityService: GigyaIdentityService,
        atresPlayer: any AtresPlayerFetching
    ) {
        self.client = client
        self.credentials = credentials
        self.identityService = identityService
        self.atresPlayer = atresPlayer
    }

    func resolve(
        _ request: PlaybackRequest,
        progress: @escaping @Sendable (PreparationPhase) async -> Void
    ) async throws -> ResolvedStream {
        do {
            switch request {
            case .channel(let channel):
                if channel.source == .direct {
                    await progress(.loadingPlayer)
                    return try resolveDirect(channel)
                }
                if channel.source == .atresplayer {
                    await progress(.resolvingMetadata)
                    return try await resolveAtresLive(channel, progress: progress)
                }
                await progress(.resolvingMetadata)
                return try await resolveLive(channel, progress: progress)
            case .video(let card):
                await progress(.resolvingMetadata)
                if let ref = AtresContentRef(pageURL: card.pageURL) {
                    return try await resolveAtresVideo(card, ref: ref, progress: progress)
                }
                return try await resolveVideo(card, progress: progress)
            case .downloaded(let stream):
                await progress(.loadingPlayer)
                return stream
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as PlaybackFailure {
            throw failure
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        } catch {
            throw PlaybackFailure.apiChanged
        }
    }

    private func resolveAtresLive(
        _ channel: Channel,
        progress: @escaping @Sendable (PreparationPhase) async -> Void
    ) async throws -> ResolvedStream {
        guard let channelID = channel.slug?.trimmedNonEmpty else {
            throw PlaybackFailure.invalidChannel
        }
        let result = try await atresPlayer.resolveLive(channelID: channelID)
        await progress(.loadingPlayer)
        return ResolvedStream(
            title: channel.name,
            url: result.streamURL,
            headers: AtresAPIConfiguration.playbackHeaders,
            allowsHeaderFallback: true,
            subtitles: [],
            artworkURL: nil,
            isLive: true,
            contentID: nil
        )
    }

    private func resolveAtresVideo(
        _ card: MediaCard,
        ref: AtresContentRef,
        progress: @escaping @Sendable (PreparationPhase) async -> Void
    ) async throws -> ResolvedStream {
        let result: AtresPlayableResult
        switch ref {
        case .episode(let contentID):
            result = try await atresPlayer.resolveEpisode(contentID: contentID)
        case .recording(let contentID):
            result = try await atresPlayer.resolveRecording(contentID: contentID)
        case .movieFormat(let formatID):
            result = try await atresPlayer.resolveMovie(formatID: formatID)
        }
        await progress(.loadingPlayer)
        let subtitles = result.subtitleURL.map { [SubtitleTrack(url: $0, languageTag: "es")] } ?? []
        return ResolvedStream(
            title: card.title,
            url: result.streamURL,
            headers: AtresAPIConfiguration.playbackHeaders,
            allowsHeaderFallback: true,
            subtitles: subtitles,
            artworkURL: card.artworkURL,
            isLive: false,
            contentID: card.id
        )
    }

    private func resolveDirect(_ channel: Channel) throws -> ResolvedStream {
        guard let url = channel.directURL, url.scheme == "https" else {
            throw PlaybackFailure.invalidChannel
        }
        let headers: [String: String]
        switch channel.headerProfile {
        case .rtve:
            headers = APIConfiguration.rtvePlaybackHeaders
        case .mediaset:
            headers = APIConfiguration.mediasetPlaybackHeaders
        case .atresplayer:
            headers = AtresAPIConfiguration.playbackHeaders
        case .none:
            headers = [:]
        }
        return ResolvedStream(
            title: channel.name,
            url: url,
            headers: headers,
            allowsHeaderFallback: !headers.isEmpty,
            subtitles: [],
            artworkURL: nil,
            isLive: true,
            contentID: nil
        )
    }

    private func resolveLive(
        _ channel: Channel,
        progress: @escaping @Sendable (PreparationPhase) async -> Void
    ) async throws -> ResolvedStream {
        guard let slug = channel.slug?.trimmedNonEmpty else {
            throw PlaybackFailure.invalidChannel
        }
        guard let credentials = try await credentials.credentials(), credentials.isValid else {
            throw PlaybackFailure.missingCredentials
        }
        let headers = APIConfiguration.sessionHeaders(gmid: credentials.gmid)
        let caronteURL = try liveCaronteURL(slug: slug)
        let gbxURL = try APIURL.mabURL(
            oid: "mtmw",
            eid: "/api/mtmw/v3/gbx/mtweb/\(slug)"
        )

        async let caronte = fetchCaronte(url: caronteURL, headers: headers)
        async let gbx = fetchGBX(url: gbxURL, headers: headers)
        let delivery = try await (caronte, gbx)
        await progress(.authorizing)
        // Live channels have no episode page to resolve a finder guid from, so they can never take
        // the FairPlay path — `fairPlayStream` throws `unavailableClearStream` if ever reached.
        let signed = try await signedURL(caronte: delivery.0, gbx: delivery.1, pageURL: nil)
        await progress(.loadingPlayer)
        return ResolvedStream(
            title: channel.name,
            url: signed.url,
            headers: APIConfiguration.mediasetPlaybackHeaders,
            allowsHeaderFallback: true,
            subtitles: subtitleTracks(from: delivery.0),
            artworkURL: nil,
            isLive: true,
            contentID: nil,
            drm: signed.drm
        )
    }

    private func resolveVideo(
        _ card: MediaCard,
        progress: @escaping @Sendable (PreparationPhase) async -> Void
    ) async throws -> ResolvedStream {
        guard let credentials = try await credentials.credentials(), credentials.isValid else {
            throw PlaybackFailure.missingCredentials
        }
        let sessionHeaders = APIConfiguration.sessionHeaders(gmid: credentials.gmid)
        let programmeURL = try normalizedProgrammeURL(card.pageURL)
        let prePlayerEID = "/v2/prePlayer/mtand?url=\(programmeURL.absoluteString)"
        let prePlayerURL = try APIURL.mabURL(oid: "bitban", eid: prePlayerEID)
        let prePlayer = try await client.decode(
            PrePlayerResponse.self,
            from: Endpoint(url: prePlayerURL, headers: sessionHeaders)
        )
        guard let editorialID = prePlayer.editorialID?.trimmedNonEmpty else {
            throw PlaybackFailure.apiChanged
        }

        let configEID = "/api/v2/mitele/videos/\(editorialID)/config/final.json?platform=mtand"
        let configURL = try APIURL.mabURL(oid: "bitban_api", eid: configEID)
        let configuration = try await client.decode(
            ServicesResponse.self,
            from: Endpoint(url: configURL, headers: sessionHeaders)
        )
        guard let gbxURL = configuration.serviceURL(named: "gbx"),
              let caronteURL = configuration.serviceURL(named: "caronte") else {
            throw PlaybackFailure.apiChanged
        }

        async let caronte = fetchCaronte(
            url: caronteURL,
            headers: APIConfiguration.deliveryHeaders
        )
        async let gbx = fetchGBX(
            url: gbxURL,
            headers: APIConfiguration.deliveryHeaders
        )
        let delivery = try await (caronte, gbx)
        await progress(.authorizing)
        let signed = try await signedURL(caronte: delivery.0, gbx: delivery.1, pageURL: card.pageURL)
        await progress(.loadingPlayer)
        return ResolvedStream(
            title: card.title,
            url: signed.url,
            headers: APIConfiguration.mediasetPlaybackHeaders,
            allowsHeaderFallback: true,
            subtitles: subtitleTracks(from: delivery.0),
            artworkURL: card.artworkURL,
            isLive: false,
            contentID: card.id,
            drm: signed.drm
        )
    }

    private func subtitleTracks(from caronte: CaronteResponse) -> [SubtitleTrack] {
        caronte.resolvedSubtitles.compactMap { dto in
            guard let vtt = dto.vtt?.trimmedNonEmpty, let url = URL(string: vtt), url.scheme == "https" else {
                return nil
            }
            return SubtitleTrack(url: url, languageTag: "es")
        }
    }

    /// A signed, playable manifest — clear when the CDN offers one, otherwise the FairPlay
    /// variant with the DRM parameters AVPlayer needs to acquire a content key.
    private struct SignedStream {
        let url: URL
        let drm: FairPlayDRM?
    }

    private func signedURL(caronte: CaronteResponse, gbx: String, pageURL: URL?) async throws -> SignedStream {
        guard let stream = caronte.stream?.trimmedNonEmpty,
              let bbx = caronte.resolvedBBX?.trimmedNonEmpty else {
            throw PlaybackFailure.apiChanged
        }
        let identity = try await identityService.identity()
        let payload = CerberoPayload(
            gid: identity.uid,
            time: identity.timestamp,
            sig: identity.signature,
            gbx: gbx,
            bbx: bbx
        )
        let body = try JSONEncoder().encode(payload)
        let endpoint = Endpoint(
            url: APIURL.cerbero,
            method: "POST",
            headers: APIConfiguration.cerberoHeaders,
            body: body
        )
        let response = try await client.decode(CerberoResponse.self, from: endpoint)
        guard let token = response.tokens?["1"]?.cdn?.trimmedNonEmpty else {
            if response.errorCode != nil { throw PlaybackFailure.sessionExpired }
            throw PlaybackFailure.apiChanged
        }
        return try await manifest(stream: stream, token: token, caronte: caronte, pageURL: pageURL)
    }

    /// Chooses between the clear and FairPlay variants of a signed stream.
    ///
    /// Most uploads carry a clear `main.ism` beside the encrypted `hls-fairplay.ism`, and the app
    /// prefers it (no DRM, so it also downloads). Some are packaged FairPlay-only, and the CDN
    /// then answers the clear manifest with `403`/`404`; those play through AVPlayer's FairPlay
    /// path using the DRM parameters from the same caronte response.
    private func manifest(
        stream: String,
        token: String,
        caronte: CaronteResponse,
        pageURL: URL?
    ) async throws -> SignedStream {
        let cleanToken = String(token.drop(while: { $0 == "?" || $0 == "&" }))
        let lowercased = stream.lowercased()

        if lowercased.contains("hls-fairplay.ism") {
            let clearStream = stream.replacingOccurrences(
                of: "hls-fairplay.ism",
                with: "main.ism",
                options: [.caseInsensitive]
            )
            if let clearURL = tokenizedURL(stream: clearStream, token: cleanToken),
               await clearVariantIsPlayable(clearURL) {
                return SignedStream(url: clearURL, drm: nil)
            }
            return try await fairPlayStream(stream: stream, token: cleanToken, caronte: caronte, pageURL: pageURL)
        }

        if lowercased.contains("fairplay") {
            return try await fairPlayStream(stream: stream, token: cleanToken, caronte: caronte, pageURL: pageURL)
        }

        guard let url = tokenizedURL(stream: stream, token: cleanToken) else {
            throw PlaybackFailure.invalidURL
        }
        return SignedStream(url: url, drm: nil)
    }

    private func fairPlayStream(
        stream: String,
        token: String,
        caronte: CaronteResponse,
        pageURL: URL?
    ) async throws -> SignedStream {
        guard let certURLString = caronte.resolvedFairPlay?.curl?.trimmedNonEmpty,
              let certificateURL = URL(string: certURLString), certificateURL.scheme == "https",
              let url = tokenizedURL(stream: stream, token: token) else {
            throw PlaybackFailure.unavailableClearStream
        }
        // Entitlement (and the real theplatform pid/account the license needs) is resolved via
        // Mediaset's `playback/check` + SMIL selector chain — see `fairPlaySelector`.
        let selector = try await fairPlaySelector(pageURL: pageURL)
        guard let licenseURL = Self.fairPlayLicenseURL(account: selector.aid) else {
            throw PlaybackFailure.unavailableClearStream
        }
        let drm = FairPlayDRM(
            certificateURL: certificateURL,
            licenseURL: licenseURL,
            releasePid: selector.pid,
            token: selector.beToken,
            licenseHeaders: APIConfiguration.ottHeaders
        )
        return SignedStream(url: url, drm: drm)
    }

    // MARK: - FairPlay/Widevine entitlement chain
    //
    // Mirrors the flow a working Kodi addon uses for this same catalog's Widevine licensing:
    //   1. anonymous IDM login → {sid, beToken} (no user account involved — entitlement here is
    //      per-content via `playback/check`, not per-subscriber)
    //   2. scrape the episode page for its M-prefixed theplatform "finder" guid
    //   3. POST playback/v3.0/check(contentId: guid) → a SMIL media-selector URL + passthrough params
    //   4. GET that SMIL selector → its `trackingData` param carries `pid` (the release pid) and
    //      `aid` (the account id), the two identifiers theplatform's license servers actually check
    // `pid` doubles as the FairPlay SPC's content identifier; `beToken` is the license `token=`.

    private struct FairPlaySelector {
        let pid: String
        let aid: String
        let beToken: String
    }

    private func fairPlaySelector(pageURL: URL?) async throws -> FairPlaySelector {
        guard let pageURL else {
            // No episode page to resolve a finder guid from (e.g. a live channel).
            throw PlaybackFailure.unavailableClearStream
        }
        let guid = try await programGUID(pageURL: pageURL)
        let login = try await anonymousLogin()
        let selector = try await playbackCheck(contentID: guid, sid: login.sid, beToken: login.beToken)
        let smil = try await fetchSMIL(
            selectorURL: selector.url,
            passthrough: selector.passthrough,
            beToken: login.beToken
        )
        guard let tracking = Self.trackingData(from: smil),
              let pid = tracking["pid"]?.trimmedNonEmpty,
              let aid = tracking["aid"]?.trimmedNonEmpty else {
            throw PlaybackFailure.apiChanged
        }
        return FairPlaySelector(pid: pid, aid: aid, beToken: login.beToken)
    }

    /// Fetches (and caches) an anonymous IDM login. No user credentials are involved — Mediaset's
    /// entitlement for this catalog is evaluated per-content by `playback/check`, not per-account.
    private func anonymousLogin() async throws -> (sid: String, beToken: String) {
        if let cached = cachedAnonymousLogin, cached.expiry > Date.now.addingTimeInterval(60) {
            return (cached.sid, cached.beToken)
        }
        let body = try JSONEncoder().encode(
            AnonymousLoginRequest(client_id: UUID().uuidString.lowercased(), appName: APIURL.mediasetInfinityAppName)
        )
        var headers = APIConfiguration.ottHeaders
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json"
        let endpoint = Endpoint(
            url: APIURL.idmAnonymousLogin,
            method: "POST",
            headers: headers,
            body: body
        )
        let response = try await client.decode(AnonymousLoginResponse.self, from: endpoint)
        guard let sid = response.response?.sid?.trimmedNonEmpty,
              let beToken = response.response?.beToken?.trimmedNonEmpty else {
            throw PlaybackFailure.apiChanged
        }
        cachedAnonymousLogin = (sid, beToken, Self.jwtExpiry(beToken) ?? Date.now.addingTimeInterval(3600))
        return (sid, beToken)
    }

    /// Scrapes the episode's `mediasetinfinity.es` page for its embedded finder guid
    /// (`link-ott-prod.mediaset.net/finder/esp/{guid}`) — the `contentId` `playback/check` expects.
    private func programGUID(pageURL: URL) async throws -> String {
        let url = try infinityProgrammeURL(pageURL)
        let data = try await client.data(for: Endpoint(url: url, headers: APIConfiguration.scrapeHeaders, timeout: 20))
        guard let html = String(data: data, encoding: .utf8) else { throw PlaybackFailure.apiChanged }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = Self.finderGUIDRegex.firstMatch(in: html, range: range),
              let guidRange = Range(match.range(at: 1), in: html) else {
            throw PlaybackFailure.apiChanged
        }
        return String(html[guidRange])
    }

    private func playbackCheck(
        contentID: String,
        sid: String,
        beToken: String
    ) async throws -> (url: URL, passthrough: [String: String]) {
        guard var components = URLComponents(url: APIURL.playbackCheck, resolvingAgainstBaseURL: false) else {
            throw PlaybackFailure.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "sid", value: sid)]
        guard let requestURL = components.url else { throw PlaybackFailure.invalidURL }

        let body = try JSONSerialization.data(withJSONObject: [
            "contentId": contentID,
            "streamType": "VOD",
            "delivery": "Streaming"
        ])
        var headers = APIConfiguration.ottHeaders
        headers["Authorization"] = "Bearer \(beToken)"
        headers["Content-Type"] = "application/json"
        let data = try await client.data(for: Endpoint(url: requestURL, method: "POST", headers: headers, body: body))

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["response"] as? [String: Any],
              let selector = response["mediaSelector"] as? [String: Any],
              let urlString = selector["url"] as? String,
              let selectorURL = URL(string: urlString) else {
            throw PlaybackFailure.apiChanged
        }
        var passthrough: [String: String] = [:]
        for key in ["formats", "assetTypes", "tracking", "delivery", "publicUrl"] {
            if let value = selector[key], let text = Self.stringify(value) {
                passthrough[key] = text
            }
        }
        return (selectorURL, passthrough)
    }

    private func fetchSMIL(selectorURL: URL, passthrough: [String: String], beToken: String) async throws -> String {
        guard var components = URLComponents(url: selectorURL, resolvingAgainstBaseURL: false) else {
            throw PlaybackFailure.invalidURL
        }
        var items = components.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "format", value: "SMIL"),
            URLQueryItem(name: "auto", value: "true"),
            URLQueryItem(name: "balance", value: "true")
        ])
        for (key, value) in passthrough {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        guard let url = components.url else { throw PlaybackFailure.invalidURL }

        var headers = APIConfiguration.ottHeaders
        headers["Authorization"] = "Basic \(Data(":\(beToken)".utf8).base64EncodedString())"
        let data = try await client.data(for: Endpoint(url: url, headers: headers))
        guard let text = String(data: data, encoding: .utf8) else { throw PlaybackFailure.apiChanged }
        return text
    }

    private func infinityProgrammeURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            throw PlaybackFailure.invalidURL
        }
        if host.hasSuffix("mitele.es") {
            let prefix = host.dropLast("mitele.es".count)
            components.host = "\(prefix)mediasetinfinity.es"
        }
        guard let result = components.url else { throw PlaybackFailure.invalidURL }
        return result
    }

    private static let finderGUIDRegex = try! NSRegularExpression(
        pattern: #"link-ott-prod\.mediaset\.net/finder/esp/(\w+)"#
    )

    /// Finds the `<param name="trackingData" value="pid=…|aid=…|…">` inside a SMIL document and
    /// parses its pipe-delimited `key=value` pairs (forgiving of malformed pairs, matching the
    /// reference implementation this was ported from).
    private static func trackingData(from smil: String) -> [String: String]? {
        guard let paramTagRegex = try? NSRegularExpression(pattern: #"<param\b[^>]*>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(smil.startIndex..., in: smil)
        for match in paramTagRegex.matches(in: smil, range: range) {
            guard let tagRange = Range(match.range, in: smil) else { continue }
            let tag = String(smil[tagRange])
            guard tag.range(of: #"name\s*=\s*"trackingData""#, options: .regularExpression) != nil,
                  let valueRange = tag.range(of: #"value\s*=\s*"([^"]*)""#, options: .regularExpression) else {
                continue
            }
            var value = String(tag[valueRange])
            value = value.replacingOccurrences(of: #"^value\s*=\s*""#, with: "", options: .regularExpression)
            if value.hasSuffix("\"") { value.removeLast() }
            value = value.replacingOccurrences(of: "&amp;", with: "&")

            var result: [String: String] = [:]
            for pair in value.split(separator: "|") {
                guard let eq = pair.firstIndex(of: "=") else { continue }
                let key = String(pair[pair.startIndex..<eq])
                let val = String(pair[pair.index(after: eq)...])
                result[key] = val
            }
            if !result.isEmpty { return result }
        }
        return nil
    }

    private static func stringify(_ value: Any) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        case let array as [Any]: return array.compactMap { stringify($0) }.joined(separator: ",")
        default: return nil
        }
    }

    private static func fairPlayLicenseURL(account aid: String) -> URL? {
        guard var components = URLComponents(url: APIURL.fairPlayLicenseBase, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "httpError", value: "true"),
            URLQueryItem(name: "form", value: "json"),
            URLQueryItem(name: "account", value: "http://access.auth.theplatform.com/data/Account/\(aid)"),
            URLQueryItem(name: "schema", value: "1.0")
        ]
        return components.url
    }

    /// Reads the `exp` (seconds since epoch) from a JWT's payload, for cache lifetime.
    private static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private func tokenizedURL(stream: String, token: String) -> URL? {
        let separator = stream.contains("?") ? "&" : "?"
        guard let url = URL(string: stream + separator + token), url.scheme == "https" else {
            return nil
        }
        return url
    }

    /// The clear `main.ism` variant isn't guaranteed to exist — FairPlay-only uploads make the
    /// CDN answer it with `403`/`404` even with a valid token. A `false` result routes playback to
    /// FairPlay instead. Transport errors are treated as "playable" so a flaky probe doesn't push
    /// a stream to DRM that AVPlayer might otherwise manage clear.
    private func clearVariantIsPlayable(_ url: URL) async -> Bool {
        let endpoint = Endpoint(url: url, headers: APIConfiguration.mediasetPlaybackHeaders, timeout: 15)
        guard let (status, _) = try? await client.rawData(for: endpoint) else {
            return true
        }
        return status != 403 && status != 404
    }

    private func fetchCaronte(url: URL, headers: [String: String]) async throws -> CaronteResponse {
        try await client.decode(
            CaronteResponse.self,
            from: Endpoint(url: url, headers: headers)
        )
    }

    private func fetchGBX(url: URL, headers: [String: String]) async throws -> String {
        let response = try await client.decode(
            GBXResponse.self,
            from: Endpoint(url: url, headers: headers)
        )
        guard let gbx = response.resolvedGBX?.trimmedNonEmpty else {
            throw PlaybackFailure.apiChanged
        }
        return gbx
    }

    private func liveCaronteURL(slug: String) throws -> URL {
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://caronte.mediaset.es/delivery/channel/mmc/\(encoded)/mtweb") else {
            throw PlaybackFailure.invalidChannel
        }
        return url
    }

    private func normalizedProgrammeURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            throw PlaybackFailure.invalidURL
        }
        if host.hasSuffix("mediasetinfinity.es") {
            let prefix = host.dropLast("mediasetinfinity.es".count)
            components.host = "\(prefix)mitele.es"
        }
        guard let result = components.url else { throw PlaybackFailure.invalidURL }
        return result
    }

}

private struct PrePlayerResponse: Decodable, Sendable {
    struct Video: Decodable, Sendable {
        let dataEditorialId: String?
    }

    struct Wrapper: Decodable, Sendable {
        let video: Video?
    }

    let video: Video?
    let response: Wrapper?

    var editorialID: String? {
        video?.dataEditorialId ?? response?.video?.dataEditorialId
    }
}

private struct ServicesResponse: Decodable, Sendable {
    struct Wrapper: Decodable, Sendable {
        let services: [String: String]?
    }

    let services: [String: String]?
    let response: Wrapper?

    func serviceURL(named name: String) -> URL? {
        let value = services?[name] ?? response?.services?[name]
        guard let value, let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }
}

private struct CaronteResponse: Decodable, Sendable {
    struct Delivery: Decodable, Sendable {
        let stream: String?
    }

    struct SubtitleDTO: Decodable, Sendable {
        let vtt: String?
    }

    struct FairPlayDTO: Decodable, Sendable {
        /// Application certificate — the only field still used; the license URL and its
        /// `releasePid`/`account` are resolved separately (see `MediasetStreamResolver`'s
        /// `playback/check` + SMIL selector chain), not from this templated `lurl`.
        let curl: String?
    }

    struct DRMDTO: Decodable, Sendable {
        let fairplay: FairPlayDTO?
    }

    struct Wrapper: Decodable, Sendable {
        let dls: [Delivery]?
        let bbx: String?
        let subtitles: [SubtitleDTO]?
        let drm: DRMDTO?
    }

    let dls: [Delivery]?
    let bbx: String?
    let subtitles: [SubtitleDTO]?
    let drm: DRMDTO?
    let response: Wrapper?

    var stream: String? { dls?.first?.stream ?? response?.dls?.first?.stream }
    var resolvedBBX: String? { bbx ?? response?.bbx }
    var resolvedSubtitles: [SubtitleDTO] { subtitles ?? response?.subtitles ?? [] }
    var resolvedFairPlay: FairPlayDTO? { drm?.fairplay ?? response?.drm?.fairplay }

    init(from decoder: Decoder) throws {
        enum CodingKeys: String, CodingKey { case dls, bbx, subtitles, drm, response }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dls = try? container.decode([Delivery].self, forKey: .dls)
        subtitles = try? container.decode([SubtitleDTO].self, forKey: .subtitles)
        bbx = try? container.decode(String.self, forKey: .bbx)
        drm = try? container.decode(DRMDTO.self, forKey: .drm)
        response = try? container.decode(Wrapper.self, forKey: .response)
    }
}

private struct GBXResponse: Decodable, Sendable {
    struct Wrapper: Decodable, Sendable { let gbx: String? }
    let gbx: String?
    let response: Wrapper?
    var resolvedGBX: String? { gbx ?? response?.gbx }
}

private struct AnonymousLoginRequest: Encodable, Sendable {
    let client_id: String
    let appName: String
}

private struct AnonymousLoginResponse: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let sid: String?
        let beToken: String?
    }
    let response: Body?
}

private struct CerberoPayload: Encodable, Sendable {
    let gid: String
    let time: Int64
    let sig: String
    let gbx: String
    let bbx: String
}

private struct CerberoResponse: Decodable, Sendable {
    struct Token: Decodable, Sendable { let cdn: String? }
    let tokens: [String: Token]?
    let errorCode: Int?
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
