import Foundation

/// The user's own Atresplayer login cookie (`A3PSID`), baked in as a starting default the same
/// way `DefaultCredentials` bakes in the Mediaset GMID/COOKIE pair — editable from Settings.
/// Session cookies expire/rotate periodically; update the value in Settings if playback of
/// gated content starts failing.
enum AtresDefaultCredentials {
    static let session = "e-K43h4C-mHt2iEuwLAjVBQZRI9fbQ8wwZqywYUw10cw_Q5zUt3qTe-eeC95gIqOtn4lQECSD94C3bjk1r2AVA"
}

/// Atresplayer's API is a plain REST/JSON service — no GraphQL, no persisted-query hashes, no
/// Cerbero/Gigya-style signing chain. A single desktop User-Agent is sufficient for every
/// endpoint (browsing, all three player endpoints, manifests, and subtitle files); no
/// Referer/Origin/Accept requirements were found necessary. See API_STREAM_RESOLUTION_ATRES.md.
enum AtresAPIConfiguration {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36"

    static let headers = ["User-Agent": userAgent]

    static let playbackHeaders = ["User-Agent": userAgent]

    /// `player/v1/episode` (only) can demand a registered/paid session — attach the user's own
    /// `A3PSID` login cookie as a plain `Cookie` header, nothing more (no signing, no token
    /// exchange). See API_STREAM_RESOLUTION_ATRES.md §3.4. Accepts either the bare token or a
    /// full `A3PSID=...` string, since browser dev tools copy it either way depending on view.
    static func authenticatedHeaders(session: String) -> [String: String] {
        var headers = headers
        headers["Cookie"] = session.hasPrefix("A3PSID=") ? session : "A3PSID=\(session)"
        return headers
    }
}

enum AtresAPIURL {
    static let base = URL(string: "https://api.atresplayer.com/")!

    static func row(_ rowID: String) -> URL {
        base.appendingPathComponent("client/v1/row/\(rowID)")
    }

    static let rowSearch = base.appendingPathComponent("client/v1/row/search")

    static func formatPage(_ formatID: String) -> URL {
        base.appendingPathComponent("client/v1/page/format/\(formatID)")
    }

    static func episodePlayer(_ contentID: String) -> URL {
        base.appendingPathComponent("player/v1/episode/\(contentID)")
    }

    static func recordingPlayer(_ contentID: String) -> URL {
        base.appendingPathComponent("player/v1/recording/\(contentID)")
    }

    static func livePlayer(_ channelID: String) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent("player/v1/live/\(channelID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "NODRM", value: "true")]
        return components.url!
    }
}

/// Hardcoded catalog/category ids captured from the addon's source — Atresplayer has no
/// equivalent to Mediaset's persisted-query hashes, these are just fixed row/category ids.
/// See API_STREAM_RESOLUTION_ATRES.md §18/§19.
enum AtresCatalogID {
    static let globalChannelID = "5a6b32667ed1a834493ec03b"
    static let categoryProgramas = "5a6a1ba0986b281d18a512b9"
    static let categorySeries = "5a6a1b22986b281d18a512b8"
    static let categoryCine = "5b5f2f777ed1a86860102144"
}

/// Builds the fixed (page/size-less) base URLs for the two catalog shapes — `AtresRowService`
/// appends `size`/`page` itself. See API_STREAM_RESOLUTION_ATRES.md §4.4/§18.2.
enum AtresCatalogURLBuilder {
    static func formatSearch(categoryID: String, sortType: String = "AZ") -> URL {
        var components = URLComponents(url: AtresAPIURL.rowSearch, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "entityType", value: "ATPFormat"),
            URLQueryItem(name: "sectionCategory", value: "true"),
            URLQueryItem(name: "mainChannelId", value: AtresCatalogID.globalChannelID),
            URLQueryItem(name: "categoryId", value: categoryID),
            URLQueryItem(name: "sortType", value: sortType)
        ]
        return components.url!
    }

    static func recordingSearch(categoryID: String) -> URL {
        var components = URLComponents(url: AtresAPIURL.rowSearch, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "entityType", value: "ATPRecording"),
            URLQueryItem(name: "categoryId", value: categoryID)
        ]
        return components.url!
    }
}
