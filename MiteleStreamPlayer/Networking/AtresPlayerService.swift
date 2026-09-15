import Foundation

struct AtresPlayableResult: Sendable {
    let title: String
    let streamURL: URL
    let subtitleURL: URL?
}

protocol AtresPlayerFetching: Sendable {
    func resolveEpisode(contentID: String) async throws -> AtresPlayableResult
    func resolveRecording(contentID: String) async throws -> AtresPlayableResult
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

    func resolveLive(channelID: String) async throws -> AtresPlayableResult {
        let endpoint = Endpoint(url: AtresAPIURL.livePlayer(channelID), headers: AtresAPIConfiguration.headers)
        do {
            let response = try await client.decode(AtresPlayerResponse.self, from: endpoint)
            guard let streamURL = Self.bestSource(response.sourcesLive) else {
                throw PlaybackFailure.apiChanged
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
    /// cookie on every request just because one happens to be configured.
    private func resolveVOD(url: URL) async throws -> AtresPlayableResult {
        do {
            return try await fetchPlayable(url: url, headers: AtresAPIConfiguration.headers)
        } catch let error as HTTPClientError where Self.isAuthGate(error) {
            guard let session = (try? await sessionProvider.session()) ?? nil, !session.isEmpty else {
                throw Self.mapAuthAware(error)
            }
            do {
                return try await fetchPlayable(url: url, headers: AtresAPIConfiguration.authenticatedHeaders(session: session))
            } catch let retryError as HTTPClientError {
                throw Self.mapAuthAware(retryError)
            }
        } catch let error as HTTPClientError {
            throw Self.mapAuthAware(error)
        }
    }

    private func fetchPlayable(url: URL, headers: [String: String]) async throws -> AtresPlayableResult {
        let endpoint = Endpoint(url: url, headers: headers)
        let response = try await client.decode(AtresPlayerResponse.self, from: endpoint)
        guard let streamURL = Self.bestSource(response.sources) else {
            throw PlaybackFailure.apiChanged
        }
        let subtitleURL = try? await resolveSubtitle(masterPlaylistURL: streamURL)
        return AtresPlayableResult(
            title: response.titulo?.nilIfBlank ?? "Vídeo",
            streamURL: streamURL,
            subtitleURL: subtitleURL
        )
    }

    private static func isAuthGate(_ error: HTTPClientError) -> Bool {
        if case .status(401) = error { return true }
        if case .status(403) = error { return true }
        return false
    }

    /// `player/v1/episode` (only) can gate scripted-series content behind either
    /// `required_registered` (needs any account) or `required_paid` (needs a subscription) —
    /// this app has no login flow of its own, so both map to the same "can't play this" failure
    /// rather than the Mediaset-specific "update your GMID/COOKIE" wording `.sessionExpired`
    /// carries. A configured `A3PSID` (see `resolveVOD`) covers the registered case; the paid
    /// case has no way to be satisfied by this app either way.
    private static func mapAuthAware(_ error: HTTPClientError) -> PlaybackFailure {
        if case .status(401) = error { return .requiresAccount }
        if case .status(403) = error { return .requiresAccount }
        return error.playbackFailure
    }

    private static func bestSource(_ sources: [AtresPlayerResponse.SourceDTO]?) -> URL? {
        guard let sources else { return nil }
        if let match = sources.first(where: { ($0.type ?? "").contains("apple.mpegurl") && !($0.src ?? "").isEmpty }),
           let src = match.src {
            return URL(string: src)
        }
        if let match = sources.first(where: { !($0.src ?? "").isEmpty }), let src = match.src {
            return URL(string: src)
        }
        return nil
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

private struct AtresPlayerResponse: Decodable, Sendable {
    struct SourceDTO: Decodable, Sendable {
        let src: String?
        let type: String?
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
