import Foundation

protocol AtresFormatPageFetching: Sendable {
    func fetchSeasons(formatID: String) async throws -> [Season]
    func fetchEpisodes(formatID: String, seasonID: String, page: Int) async throws -> AtresPage<MediaCard>
}

/// Wraps the format (show) detail page and the season-scoped episode listing.
/// See API_STREAM_RESOLUTION_ATRES.md §4.2/§4.3.
struct AtresFormatPageService: AtresFormatPageFetching, Sendable {
    let client: HTTPClient

    /// `seasons[]` on the format page carries no id of its own — it's embedded in
    /// `link.href`'s `seasonId` query parameter — but the title is already right there, so a
    /// single format-page fetch is enough; no need for the per-season re-fetch the doc describes
    /// (that's only needed for a season's own `description`, which this app doesn't use).
    func fetchSeasons(formatID: String) async throws -> [Season] {
        let response = try await fetchFormatPage(formatID: formatID)
        return (response.seasons ?? []).compactMap(Season.init(atres:))
    }

    func fetchEpisodes(formatID: String, seasonID: String, page: Int) async throws -> AtresPage<MediaCard> {
        guard var components = URLComponents(url: AtresAPIURL.rowSearch, resolvingAgainstBaseURL: false) else {
            throw PlaybackFailure.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "entityType", value: "ATPEpisode"),
            URLQueryItem(name: "formatId", value: formatID),
            URLQueryItem(name: "seasonId", value: seasonID),
            URLQueryItem(name: "size", value: "24"),
            URLQueryItem(name: "page", value: String(page))
        ]
        guard let url = components.url else { throw PlaybackFailure.invalidURL }

        let endpoint = Endpoint(url: url, headers: AtresAPIConfiguration.headers)
        do {
            let response = try await client.decode(AtresEpisodeRowResponse.self, from: endpoint)
            let items = (response.itemRows ?? []).compactMap(MediaCard.init(atresEpisode:))
            let hasNext = response.pageInfo?.hasNext == true
            return AtresPage(items: items, nextPage: hasNext ? page + 1 : nil)
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
    }

    private func fetchFormatPage(formatID: String) async throws -> AtresFormatPageResponse {
        let endpoint = Endpoint(url: AtresAPIURL.formatPage(formatID), headers: AtresAPIConfiguration.headers)
        do {
            return try await client.decode(AtresFormatPageResponse.self, from: endpoint)
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
    }
}

private struct AtresFormatPageResponse: Decodable, Sendable {
    struct SeasonDTO: Decodable, Sendable {
        struct LinkDTO: Decodable, Sendable {
            let href: String?
        }
        let title: String?
        let link: LinkDTO?
    }
    let seasons: [SeasonDTO]?
}

private struct AtresEpisodeRowResponse: Decodable, Sendable {
    struct PageInfo: Decodable, Sendable {
        let hasNext: Bool?
    }
    struct ImageDTO: Decodable, Sendable {
        let pathHorizontal: String?
        let pathVertical: String?
    }
    struct CardDTO: Decodable, Sendable {
        let title: String?
        let subTitle: String?
        let description: String?
        let image: ImageDTO?
        let contentId: String?
    }
    let itemRows: [CardDTO]?
    let pageInfo: PageInfo?
}

private extension Season {
    init?(atres dto: AtresFormatPageResponse.SeasonDTO) {
        guard let href = dto.link?.href,
              let url = URL(string: href),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let seasonID = components.queryItems?.first(where: { $0.name == "seasonId" })?.value?.nilIfBlank,
              let title = dto.title?.nilIfBlank else {
            return nil
        }
        id = seasonID
        self.title = title
    }
}

private extension MediaCard {
    init?(atresEpisode dto: AtresEpisodeRowResponse.CardDTO) {
        guard let rawID = dto.contentId?.nilIfBlank, let title = dto.title?.nilIfBlank else { return nil }
        id = "atres:\(rawID)"
        self.title = title
        subtitle = dto.subTitle?.nilIfBlank
        detail = dto.description?.nilIfBlank
        duration = nil
        artworkURL = AtresAPIConfiguration.posterURL(pathHorizontal: dto.image?.pathHorizontal, pathVertical: dto.image?.pathVertical)
        pageURL = AtresContentRef.episode(rawID).pageURL
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
