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

    /// Card `image.pathVertical`/`pathHorizontal` values are bare directory URLs, not files —
    /// fetching them directly 404s. A `{width}x{height}.jpg` file must be appended, and this CDN
    /// only serves a handful of whitelisted size combos — most others return `503`.
    ///
    /// Picking *which* whitelisted size matters more than just picking one that works: sizes the
    /// real Atresplayer web/app clients don't request are essentially never pre-generated, so the
    /// first `iOS` request for that exact size on a given image pays a one-time on-demand-resize
    /// cost — confirmed live to take 10-16 seconds on a cache miss, which is what "artwork takes
    /// very long to load" was. `640x360` (horizontal) was confirmed live to be already-cached
    /// (<0.3s) on every one of ~20 freshly-fetched, never-before-requested catalog images tried,
    /// i.e. it's a size real traffic already keeps warm — unlike the square crop this app first
    /// shipped with, which nobody else ever requests. `360x640` (vertical) is the fallback for the
    /// rare card with no horizontal image at all; it isn't quite as universally warm but is still
    /// far better than an arbitrary size. The app crops to a square client-side regardless
    /// (`SquarePosterImage`), so the source doesn't need to be square itself.
    static func posterURL(pathHorizontal: String?, pathVertical: String?) -> URL? {
        if let pathHorizontal, let base = URL(string: pathHorizontal) {
            return base.appendingPathComponent("640x360.jpg")
        }
        if let pathVertical, let base = URL(string: pathVertical) {
            return base.appendingPathComponent("360x640.jpg")
        }
        return nil
    }
}

enum AtresAPIURL {
    static let base = URL(string: "https://api.atresplayer.com/")!

    static func row(_ rowID: String) -> URL {
        base.appendingPathComponent("client/v1/row/\(rowID)")
    }

    static let rowSearch = base.appendingPathComponent("client/v1/row/search")

    /// "Todas las películas" FORMAT cards carry no seasons — their single playable episode is
    /// found by searching by `formatId` alone, with no `seasonId`. See
    /// API_STREAM_RESOLUTION_ATRES.md §16 and `AtresPlayerService.resolveMovie`.
    static func episodesByFormat(_ formatID: String) -> URL {
        var components = URLComponents(url: rowSearch, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "entityType", value: "ATPEpisode"),
            URLQueryItem(name: "formatId", value: formatID),
            URLQueryItem(name: "size", value: "1"),
            URLQueryItem(name: "page", value: "0")
        ]
        return components.url!
    }

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
    /// "Informativos" in the reference addon's menu — Noticias here.
    static let categoryInformativos = "5a6a215e986b281d18a512bc"
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

    /// Free-text FORMAT search — unlike category listings, this returns only top-level content
    /// (shows and monoChapter movies alike, never bare episodes/clips) across every Atresplayer
    /// category at once. See API_STREAM_RESOLUTION_ATRES.md §18.1 ("Buscador").
    static func formatTextSearch(text: String) -> URL {
        var components = URLComponents(url: AtresAPIURL.rowSearch, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "entityType", value: "ATPFormat"),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "size", value: "40"),
            URLQueryItem(name: "page", value: "0")
        ]
        return components.url!
    }
}
