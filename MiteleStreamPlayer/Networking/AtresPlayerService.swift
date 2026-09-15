import Foundation

struct AtresPlayableResult: Sendable {
    let title: String
    let streamURL: URL
    let subtitleURL: URL?
}

protocol AtresPlayerFetching: Sendable {
    func resolveEpisode(contentID: String) async throws -> AtresPlayableResult
    func resolveRecording(contentID: String) async throws -> AtresPlayableResult
    func resolveMovie(formatID: String) async throws -> AtresPlayableResult
    func resolveLive(channelID: String) async throws -> AtresPlayableResult
}

/// Resolves the three Atresplayer player endpoints to a final, already-playable manifest URL —
/// unlike Mitele, there's no signing/token exchange step, `sources[].src` is final. Also resolves
/// the WebVTT subtitle track by parsing the HLS master playlist's `EXT-X-MEDIA` tags, since
/// Atresplayer has no subtitle field in the player JSON at all.
/// See API_STREAM_RESOLUTION_ATRES.md §6/§7/§8.
struct AtresPlayerService: AtresPlayerFetching, Sendable {
    let client: HTTPClient
    let sessionProvider: any AtresSessionProviding

    func resolveEpisode(contentID: String) async throws -> AtresPlayableResult {
        try await resolveVOD(url: AtresAPIURL.episodePlayer(contentID))
    }

    func resolveRecording(contentID: String) async throws -> AtresPlayableResult {
        try await resolveVOD(url: AtresAPIURL.recordingPlayer(contentID))
    }

    /// "Todas las películas" cards are FORMAT-shaped, not directly playable — `formatId` itself
    /// 404s against `player/v1/episode`. Confirmed live: `client/v1/row/search?entityType=
    /// ATPEpisode&formatId={formatId}` (no `seasonId`, since these formats carry no seasons at
    /// all) returns exactly one `ATPEpisode` card, and *that* card's own `contentId` is what
    /// actually resolves. See API_STREAM_RESOLUTION_ATRES.md §16.
    func resolveMovie(formatID: String) async throws -> AtresPlayableResult {
        let contentID = try await lookupMovieEpisodeID(formatID: formatID)
        return try await resolveEpisode(contentID: contentID)
    }

    private func lookupMovieEpisodeID(formatID: String) async throws -> String {
        let endpoint = Endpoint(url: AtresAPIURL.episodesByFormat(formatID), headers: AtresAPIConfiguration.headers)
        let response: AtresEpisodeLookupResponse
        do {
            response = try await client.decode(AtresEpisodeLookupResponse.self, from: endpoint)
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
        guard let contentID = response.itemRows?.first?.contentId?.nilIfBlank else {
            throw PlaybackFailure.apiChanged
        }
        return contentID
    }

    func resolveLive(channelID: String) async throws -> AtresPlayableResult {
        let endpoint = Endpoint(url: AtresAPIURL.livePlayer(channelID), headers: AtresAPIConfiguration.headers)
        do {
            let response = try await client.decode(AtresPlayerResponse.self, from: endpoint)
            guard let streamURL = Self.bestSource(response.sourcesLive) else {
                throw Self.noClearSourceFailure(response.sourcesLive)
            }
            return AtresPlayableResult(
                title: response.titulo?.nilIfBlank ?? "Directo",
                streamURL: streamURL,
                subtitleURL: nil
            )
        } catch let error as HTTPClientError {
            throw Self.mapAuthAware(error)
        }
    }

    /// Calls unauthenticated first (most content needs no session at all, per
    /// API_STREAM_RESOLUTION_ATRES.md §3.1), and only attaches the user's own `A3PSID` cookie and
    /// retries once if the server actually asks for one (`401`/`403`). This avoids sending a
    /// cookie on every request just because one happens to be configured. The two gates need
    /// telling apart (see `AuthGate`) since a configured session can fix one but never the other —
    /// reporting both as "add a session" is actively misleading once a session is already set.
    private func resolveVOD(url: URL) async throws -> AtresPlayableResult {
        do {
            return try await fetchPlayable(url: url, headers: AtresAPIConfiguration.headers)
        } catch let gate as AuthGate {
            guard let session = (try? await sessionProvider.session()) ?? nil, !session.isEmpty else {
                throw gate.failure
            }
            do {
                return try await fetchPlayable(url: url, headers: AtresAPIConfiguration.authenticatedHeaders(session: session))
            } catch let retryGate as AuthGate {
                throw retryGate.failure
            }
        }
    }

    /// The two auth gates `player/v1/episode`/`player/v1/recording` can return both surface as a
    /// plain `403`, distinguishable only by the `error` field in the JSON body
    /// (`required_registered` vs `required_paid`) — a body `HTTPClient.decode`/`.data` discard on
    /// error, hence the raw fetch here via `rawData(for:)`.
    private enum AuthGate: Error, Sendable {
        case registered
        case paid

        var failure: PlaybackFailure {
            switch self {
            case .registered: .requiresAccount
            case .paid: .requiresSubscription
            }
        }
    }

    private struct AtresErrorDTO: Decodable, Sendable {
        let error: String?
    }

    private func fetchPlayable(url: URL, headers: [String: String]) async throws -> AtresPlayableResult {
        let raw: (status: Int, data: Data)
        do {
            raw = try await client.rawData(for: Endpoint(url: url, headers: headers))
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
        if raw.status == 401 || raw.status == 403 {
            let errorCode = (try? JSONDecoder().decode(AtresErrorDTO.self, from: raw.data))?.error
            throw errorCode == "required_paid" ? AuthGate.paid : AuthGate.registered
        }
        guard (200..<300).contains(raw.status) else {
            throw PlaybackFailure.network
        }
        guard let response = try? JSONDecoder().decode(AtresPlayerResponse.self, from: raw.data) else {
            throw PlaybackFailure.apiChanged
        }
        guard let streamURL = Self.bestSource(response.sources) else {
            throw Self.noClearSourceFailure(response.sources)
        }
        let subtitleURL = try? await resolveSubtitle(masterPlaylistURL: streamURL)
        return AtresPlayableResult(
            title: response.titulo?.nilIfBlank ?? "Vídeo",
            streamURL: streamURL,
            subtitleURL: subtitleURL
        )
    }

    /// `player/v1/live` gating is unaffected by this distinction in practice — every live channel
    /// this app lists works unauthenticated except the paid `atresplayer-premium` FAST channel,
    /// which is deliberately excluded from the seed list — so it keeps the simpler decode path.
    private static func mapAuthAware(_ error: HTTPClientError) -> PlaybackFailure {
        if case .status(401) = error { return .requiresAccount }
        if case .status(403) = error { return .requiresAccount }
        return error.playbackFailure
    }

    /// Some gated content (e.g. registered-only series) returns sources that all carry a `drm`
    /// block (FairPlay/Widevine/PlayReady) — this app implements no DRM, so those must be
    /// filtered out entirely rather than handed to `AVPlayer`, which fails to start playback on
    /// them with no useful error. Only clear, undrmed sources are ever picked.
    private static func bestSource(_ sources: [AtresPlayerResponse.SourceDTO]?) -> URL? {
        guard let sources else { return nil }
        let clearSources = sources.filter { $0.drm == nil }
        if let match = clearSources.first(where: { ($0.type ?? "").contains("apple.mpegurl") && !($0.src ?? "").isEmpty }),
           let src = match.src {
            return URL(string: src)
        }
        if let match = clearSources.first(where: { !($0.src ?? "").isEmpty }), let src = match.src {
            return URL(string: src)
        }
        return nil
    }

    /// Distinguishes "this content is DRM-only" (a real, expected outcome the UI already has
    /// wording for) from "the API response changed shape" (a `sources` field that's missing or
    /// empty outright).
    private static func noClearSourceFailure(_ sources: [AtresPlayerResponse.SourceDTO]?) -> PlaybackFailure {
        (sources?.isEmpty == false) ? .unavailableClearStream : .apiChanged
    }

    /// The addon resolves the subtitle `URI` (often a `../`-relative path) via naive string
    /// concatenation, which doesn't collapse `..` and produces a dead URL. Proper relative-URL
    /// resolution (`URL(string:relativeTo:)`) at both steps is required for this to actually work.
    private func resolveSubtitle(masterPlaylistURL: URL) async throws -> URL? {
        let masterText = try await fetchText(url: masterPlaylistURL)
        guard let subtitleLine = masterText
            .components(separatedBy: "\n")
            .first(where: { $0.uppercased().contains("TYPE=SUBTITLES") }),
            let uri = Self.extractAttribute("URI", from: subtitleLine),
            let subPlaylistURL = URL(string: uri, relativeTo: masterPlaylistURL)?.absoluteURL else {
            return nil
        }

        let subPlaylistText = try await fetchText(url: subPlaylistURL)
        guard let lastLine = subPlaylistText
            .components(separatedBy: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty && !$0.hasPrefix("#") }) else {
            return nil
        }
        return URL(string: lastLine, relativeTo: subPlaylistURL)?.absoluteURL
    }

    private func fetchText(url: URL) async throws -> String {
        let endpoint = Endpoint(url: url, headers: AtresAPIConfiguration.playbackHeaders)
        let data = try await client.data(for: endpoint)
        guard let text = String(data: data, encoding: .utf8) else { throw PlaybackFailure.apiChanged }
        return text
    }

    /// Targeted `NAME="value"` extraction rather than the addon's comma-split approach, which
    /// breaks on any other quoted attribute (e.g. `GROUP-ID`) containing a comma.
    private static func extractAttribute(_ name: String, from line: String) -> String? {
        guard let range = line.range(of: "\(name)=\"") else { return nil }
        let afterQuote = line[range.upperBound...]
        guard let endQuote = afterQuote.firstIndex(of: "\"") else { return nil }
        return String(afterQuote[..<endQuote])
    }
}

private struct AtresEpisodeLookupResponse: Decodable, Sendable {
    struct ItemDTO: Decodable, Sendable {
        let contentId: String?
    }
    let itemRows: [ItemDTO]?
}

private struct AtresPlayerResponse: Decodable, Sendable {
    struct SourceDTO: Decodable, Sendable {
        /// Presence-only marker — its shape (`fairplay`/`widevine`/`playready` keys) doesn't
        /// matter, only whether a `drm` block exists on this source at all.
        struct DRMMarker: Decodable, Sendable {}

        let src: String?
        let type: String?
        let drm: DRMMarker?
    }
    let titulo: String?
    let sources: [SourceDTO]?
    let sourcesLive: [SourceDTO]?
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
