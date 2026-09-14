import Foundation

protocol ShowCatalogFetching: Sendable {
    func fetchShows(refID: String, after: String?) async throws -> CursorPage<ShowSummary>
}

protocol EpisodeCatalogFetching: Sendable {
    func fetchEpisodes(collectionID: String, after: String?) async throws -> CursorPage<MediaCard>
}

/// Wraps the single "listing" persisted GraphQL query (`744a87fb...8535da`), which backs
/// both top-level show catalogs (Programas/Telenovelas/MTMAD) and episode listings inside a
/// collection — the only difference is which `id` (ref_id) is passed. See API_STREAM_RESOLUTION.md §4, §12, §14.3.
struct GraphQLCatalogService: ShowCatalogFetching, EpisodeCatalogFetching, Sendable {
    private struct ClientLibrary: Encodable {
        let name = "apollo-ios"
        let version = "1.24.0"
    }

    private struct PersistedQuery: Encodable {
        let sha256Hash = "744a87fb36dd66f089b2eb301bf12240fed77ba4d400fba3065fb8d6ff8535da"
        let version = 1
    }

    private struct ExtensionsPayload: Encodable {
        let clientLibrary = ClientLibrary()
        let persistedQuery = PersistedQuery()
    }

    private struct Variables: Encodable {
        let id: String
        let after: String
        let first: Int
        let pagetype = "listing"
        let context = "{\"a\":{\"flags\":[\"SHOW_TITLE\"],\"layout\":\"GRID\",\"template\":\"KEYFRAME_NOTEXT\"},\"pt\":\"listing\"}"
    }

    let client: HTTPClient

    func fetchShows(refID: String, after: String?) async throws -> CursorPage<ShowSummary> {
        let page = try await fetchPage(refID: refID, after: after)
        return CursorPage(items: page.items.compactMap(ShowSummary.init(dto:)), nextCursor: page.nextCursor)
    }

    func fetchEpisodes(collectionID: String, after: String?) async throws -> CursorPage<MediaCard> {
        let page = try await fetchPage(refID: collectionID, after: after)
        return CursorPage(items: page.items.compactMap(MediaCard.init(dto:)), nextCursor: page.nextCursor)
    }

    private func fetchPage(refID: String, after: String?) async throws -> CursorPage<ListingCardDTO> {
        let extensions = try jsonString(ExtensionsPayload())
        let variables = try jsonString(Variables(id: refID, after: after ?? "", first: 20))
        guard var components = URLComponents(url: APIURL.graphQL, resolvingAgainstBaseURL: false) else {
            throw PlaybackFailure.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "extensions", value: extensions),
            URLQueryItem(name: "variables", value: variables)
        ]
        guard let url = components.url else { throw PlaybackFailure.invalidURL }

        let endpoint = Endpoint(url: url, headers: APIConfiguration.graphQLHeaders)
        do {
            let response = try await client.decode(ListingResponse.self, from: endpoint)
            if response.data == nil, !(response.errors?.isEmpty ?? true) {
                throw PlaybackFailure.apiChanged
            }
            let connection = response.data?.result1?.itemsConnection
            let hasNext = connection?.pageInfo?.hasNextPage ?? false
            let cursor = connection?.pageInfo?.endCursor?.nilIfBlank
            return CursorPage(items: connection?.items ?? [], nextCursor: hasNext ? cursor : nil)
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PlaybackFailure.apiChanged
        }
        return string
    }
}

private struct ListingResponse: Decodable, Sendable {
    let data: ListingData?
    let errors: [ListingError]?
}

private struct ListingError: Decodable, Sendable {
    let message: String?
}

private struct ListingData: Decodable, Sendable {
    let result1: ListingResult?
}

private struct ListingResult: Decodable, Sendable {
    let itemsConnection: ItemsConnection?
}

private struct ItemsConnection: Decodable, Sendable {
    let items: [ListingCardDTO]?
    let pageInfo: PageInfo?
}

private struct PageInfo: Decodable, Sendable {
    let hasNextPage: Bool?
    let endCursor: String?
}

private struct ListingCardDTO: Decodable, Sendable {
    struct ImageDTO: Decodable, Sendable {
        let id: String?
        let r: String?
    }

    struct LinkDTO: Decodable, Sendable {
        let referenceId: String?
        let value: String?
    }

    let cardTitle: String?
    let cardText: String?
    let description: String?
    let cardEditorialMetadata: String?
    let lastPublishDate: String?
    let durationString: String?
    let cardImages: [ImageDTO]?
    let cardLink: LinkDTO?
}

private extension ShowSummary {
    init?(dto: ListingCardDTO) {
        guard let id = dto.cardLink?.referenceId?.nilIfBlank else { return nil }
        self.id = id
        title = dto.cardTitle?.nilIfBlank ?? "Mitele"
        subtitle = dto.cardText?.nilIfBlank
        posterURL = URL(
            string: "https://img-prod-api2.mediasetplay.mediaset.it/api/images/mse/v5/esp/\(id)/image_vertical/500/700?r="
        )
    }
}

private extension MediaCard {
    init?(dto: ListingCardDTO) {
        guard let link = dto.cardLink?.value,
              let pageURL = URL(string: link),
              pageURL.scheme == "https" else {
            return nil
        }
        id = dto.cardLink?.referenceId ?? pageURL.absoluteString
        title = dto.cardTitle?.nilIfBlank ?? "Episodio"
        subtitle = dto.cardEditorialMetadata?.nilIfBlank ?? dto.cardText?.nilIfBlank
        detail = dto.description?.nilIfBlank ?? dto.lastPublishDate?.nilIfBlank
        duration = dto.durationString?.nilIfBlank
        artworkURL = Self.artworkURL(from: dto.cardImages?.first)
        self.pageURL = pageURL
    }

    static func artworkURL(from image: ListingCardDTO.ImageDTO?) -> URL? {
        guard let id = image?.id?.nilIfBlank else { return nil }
        var components = URLComponents(
            string: "https://img-prod-api2.mediasetplay.mediaset.it/api/images/mp/v5/esp/\(id)/image_keyframe_poster/360/203"
        )
        if let revision = image?.r?.nilIfBlank {
            components?.queryItems = [URLQueryItem(name: "r", value: revision)]
        }
        return components?.url
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
