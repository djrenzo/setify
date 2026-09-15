import Foundation

/// Atresplayer's free-text search (`client/v1/row/search?entityType=ATPFormat&text=...`) only
/// ever returns FORMAT cards — unlike Mitele's search, there's no separate episode/clip hit type
/// to filter out. A FORMAT card is either a browsable show or, when `monoChapter` is true, a
/// single directly-playable movie (see API_STREAM_RESOLUTION_ATRES.md §16) — both map onto
/// `SearchResult` the same way the Programas/Peliculas listings do.
struct AtresSearchService: MediaSearching, Sendable {
    let client: HTTPClient

    func search(query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let endpoint = Endpoint(
            url: AtresCatalogURLBuilder.formatTextSearch(text: trimmed),
            headers: AtresAPIConfiguration.headers
        )
        do {
            let response = try await client.decode(AtresSearchResponse.self, from: endpoint)
            return (response.itemRows ?? []).compactMap(SearchResult.init(atresFormat:))
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
    }
}

private struct AtresSearchResponse: Decodable, Sendable {
    struct ImageDTO: Decodable, Sendable {
        let pathVertical: String?
        let pathHorizontal: String?
    }

    struct CardDTO: Decodable, Sendable {
        let title: String?
        let image: ImageDTO?
        let contentId: String?
        let formatId: String?
        let monoChapter: Bool?
        let category: String?
    }

    let itemRows: [CardDTO]?
}

private extension SearchResult {
    init?(atresFormat dto: AtresSearchResponse.CardDTO) {
        guard let rawID = (dto.formatId ?? dto.contentId)?.nilIfBlank, let title = dto.title?.nilIfBlank else {
            return nil
        }
        let id = "atres:\(rawID)"
        let posterURL = AtresAPIConfiguration.posterURL(pathHorizontal: dto.image?.pathHorizontal, pathVertical: dto.image?.pathVertical)
        if dto.monoChapter == true {
            self = .playable(
                MediaCard(
                    id: id,
                    title: title,
                    subtitle: nil,
                    detail: nil,
                    duration: nil,
                    artworkURL: posterURL,
                    pageURL: AtresContentRef.movieFormat(rawID).pageURL
                ),
                favoriteKind: .atresPelicula
            )
        } else {
            self = .show(
                ShowSummary(id: id, title: title, subtitle: nil, posterURL: posterURL),
                favoriteKind: Self.atresShowKind(category: dto.category)
            )
        }
    }

    /// The free-text search spans every Atresplayer category at once, unlike the per-category row
    /// listings — `category` (e.g. "Programas", "Series", "Documentales") is only used to pick the
    /// closest matching label for the Favorites tab; anything not recognized falls back to the
    /// broad "programa" bucket rather than failing to favorite the item at all.
    private static func atresShowKind(category: String?) -> FavoriteKind {
        switch category {
        case "Series": .atresSerie
        case "Noticias", "Informativos": .atresNoticia
        default: .atresPrograma
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
