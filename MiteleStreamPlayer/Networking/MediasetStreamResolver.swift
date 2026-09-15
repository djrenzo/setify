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

    init(
        client: HTTPClient,
        credentials: any CredentialProviding,
        identityService: GigyaIdentityService
    ) {
        self.client = client
        self.credentials = credentials
        self.identityService = identityService
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
                await progress(.resolvingMetadata)
                return try await resolveLive(channel, progress: progress)
            case .video(let card):
                await progress(.resolvingMetadata)
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
        let finalURL = try await signedURL(caronte: delivery.0, gbx: delivery.1)
        await progress(.loadingPlayer)
        return ResolvedStream(
            title: channel.name,
            url: finalURL,
            headers: APIConfiguration.mediasetPlaybackHeaders,
            allowsHeaderFallback: true,
            subtitles: subtitleTracks(from: delivery.0),
            artworkURL: nil,
            isLive: true,
            contentID: nil
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
        let finalURL = try await signedURL(caronte: delivery.0, gbx: delivery.1)
        await progress(.loadingPlayer)
        return ResolvedStream(
            title: card.title,
            url: finalURL,
            headers: APIConfiguration.mediasetPlaybackHeaders,
            allowsHeaderFallback: true,
            subtitles: subtitleTracks(from: delivery.0),
            artworkURL: card.artworkURL,
            isLive: false,
            contentID: card.id
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

    private func signedURL(caronte: CaronteResponse, gbx: String) async throws -> URL {
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
        return try finalManifestURL(stream: stream, token: token)
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

    private func finalManifestURL(stream: String, token: String) throws -> URL {
        let lowercased = stream.lowercased()
        let clearStream: String
        if lowercased.contains("hls-fairplay.ism") {
            clearStream = stream.replacingOccurrences(
                of: "hls-fairplay.ism",
                with: "main.ism",
                options: [.caseInsensitive]
            )
        } else if lowercased.contains("fairplay") {
            throw PlaybackFailure.unavailableClearStream
        } else {
            clearStream = stream
        }
        let cleanToken = token.drop(while: { $0 == "?" || $0 == "&" })
        let separator = clearStream.contains("?") ? "&" : "?"
        guard let url = URL(string: clearStream + separator + cleanToken), url.scheme == "https" else {
            throw PlaybackFailure.invalidURL
        }
        return url
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

    struct Wrapper: Decodable, Sendable {
        let dls: [Delivery]?
        let bbx: String?
        let subtitles: [SubtitleDTO]?
    }

    let dls: [Delivery]?
    let bbx: String?
    let subtitles: [SubtitleDTO]?
    let response: Wrapper?

    var stream: String? { dls?.first?.stream ?? response?.dls?.first?.stream }
    var resolvedBBX: String? { bbx ?? response?.bbx }
    var resolvedSubtitles: [SubtitleDTO] { subtitles ?? response?.subtitles ?? [] }

    init(from decoder: Decoder) throws {
        enum CodingKeys: String, CodingKey { case dls, bbx, subtitles, response }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dls = try? container.decode([Delivery].self, forKey: .dls)
        subtitles = try? container.decode([SubtitleDTO].self, forKey: .subtitles)
        bbx = try? container.decode(String.self, forKey: .bbx)
        response = try? container.decode(Wrapper.self, forKey: .response)
    }
}

private struct GBXResponse: Decodable, Sendable {
    struct Wrapper: Decodable, Sendable { let gbx: String? }
    let gbx: String?
    let response: Wrapper?
    var resolvedGBX: String? { gbx ?? response?.gbx }
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
