import Foundation

protocol AtresRowFetching: Sendable {
    /// FORMAT cards (shows) — Programas/Series/Cine-as-series listings.
    func fetchFormats(baseURL: URL, page: Int) async throws -> AtresPage<ShowSummary>
    /// RECORDING cards ("últimos 7 días" movies/specials) — flat, directly playable.
    func fetchRecordings(baseURL: URL, page: Int) async throws -> AtresPage<FlatCatalogItem>
    /// "Todas las películas" — also FORMAT-shaped (monoChapter, no seasons — a data-modeling
    /// quirk, see API_STREAM_RESOLUTION_ATRES.md §16), but presented and played as a flat item
    /// like a recording, not browsed into like a show.
    func fetchMovieFormats(baseURL: URL, page: Int) async throws -> AtresPage<FlatCatalogItem>
}

/// Wraps Atresplayer's single row-listing workhorse endpoint (`GET client/v1/row/{id}` or
/// `GET client/v1/row/search?...`) — a plain REST/JSON call, page-number paginated via a
/// `pageInfo.hasNext` boolean rather than Mediaset's cursor/actualPage conventions.
/// See API_STREAM_RESOLUTION_ATRES.md §4.1/§4.4.
struct AtresRowService: AtresRowFetching, Sendable {
    let client: HTTPClient

    func fetchFormats(baseURL: URL, page: Int) async throws -> AtresPage<ShowSummary> {
        let response = try await fetchRow(baseURL: baseURL, page: page)
        let items = (response.itemRows ?? []).compactMap(ShowSummary.init(atresFormat:))
        return AtresPage(items: items, nextPage: nextPage(from: response.pageInfo, requested: page))
    }

    func fetchRecordings(baseURL: URL, page: Int) async throws -> AtresPage<FlatCatalogItem> {
        let response = try await fetchRow(baseURL: baseURL, page: page)
        let items = (response.itemRows ?? []).compactMap(FlatCatalogItem.init(atresRecording:))
        return AtresPage(items: items, nextPage: nextPage(from: response.pageInfo, requested: page))
    }

    func fetchMovieFormats(baseURL: URL, page: Int) async throws -> AtresPage<FlatCatalogItem> {
        let response = try await fetchRow(baseURL: baseURL, page: page)
        let items = (response.itemRows ?? []).compactMap(FlatCatalogItem.init(atresMovieFormat:))
        return AtresPage(items: items, nextPage: nextPage(from: response.pageInfo, requested: page))
    }

    private func fetchRow(baseURL: URL, page: Int) async throws -> AtresRowResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PlaybackFailure.invalidURL
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "size", value: "24"))
        items.append(URLQueryItem(name: "page", value: String(page)))
        components.queryItems = items
        guard let url = components.url else { throw PlaybackFailure.invalidURL }

        let endpoint = Endpoint(url: url, headers: AtresAPIConfiguration.headers)
        do {
            return try await client.decode(AtresRowResponse.self, from: endpoint)
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
    }

    private func nextPage(from pageInfo: AtresRowResponse.PageInfo?, requested: Int) -> Int? {
        (pageInfo?.hasNext == true) ? requested + 1 : nil
    }
}

private struct AtresRowResponse: Decodable, Sendable {
    struct PageInfo: Decodable, Sendable {
        let hasNext: Bool?
    }

    struct ImageDTO: Decodable, Sendable {
        let pathVertical: String?
        let pathHorizontal: String?
    }

    struct CardDTO: Decodable, Sendable {
        let title: String?
        let image: ImageDTO?
        let contentId: String?
        let formatId: String?
    }

    let itemRows: [CardDTO]?
    let pageInfo: PageInfo?
}

private extension ShowSummary {
    init?(atresFormat dto: AtresRowResponse.CardDTO) {
        guard let rawID = (dto.formatId ?? dto.contentId)?.nilIfBlank, let title = dto.title?.nilIfBlank else {
            return nil
        }
        id = "atres:\(rawID)"
        self.title = title
        subtitle = nil
        posterURL = AtresAPIConfiguration.posterURL(pathHorizontal: dto.image?.pathHorizontal, pathVertical: dto.image?.pathVertical)
    }
}

private extension FlatCatalogItem {
    init?(atresRecording dto: AtresRowResponse.CardDTO) {
        guard let rawID = dto.contentId?.nilIfBlank, let title = dto.title?.nilIfBlank else { return nil }
        id = "atres:\(rawID)"
        self.title = title
        posterURL = AtresAPIConfiguration.posterURL(pathHorizontal: dto.image?.pathHorizontal, pathVertical: dto.image?.pathVertical)
        pageURL = AtresContentRef.recording(rawID).pageURL
    }

    init?(atresMovieFormat dto: AtresRowResponse.CardDTO) {
        guard let rawID = (dto.formatId ?? dto.contentId)?.nilIfBlank, let title = dto.title?.nilIfBlank else {
            return nil
        }
        id = "atres:\(rawID)"
        self.title = title
        posterURL = AtresAPIConfiguration.posterURL(pathHorizontal: dto.image?.pathHorizontal, pathVertical: dto.image?.pathVertical)
        pageURL = AtresContentRef.movieFormat(rawID).pageURL
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
