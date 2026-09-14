import Foundation

protocol MediaSearching: Sendable {
    func search(query: String) async throws -> [MediaCard]
}

struct MiteleSearchService: MediaSearching {
    private struct ClientLibrary: Encodable {
        let name = "apollo-ios"
        let version = "1.24.0"
    }

    private struct PersistedQuery: Encodable {
        let sha256Hash = "819f5ee79c4b589ce25bacbf2390d181311495e647bfff092a487b4e00552072"
        let version = 1
    }

    private struct ExtensionsPayload: Encodable {
        let clientLibrary = ClientLibrary()
        let persistedQuery = PersistedQuery()
    }

    private struct Variables: Encodable {
        let first = 40
        let property = "search"
        let query: String
        let uxReference = "filteredSearch"
    }

    let client: HTTPClient

    func search(query: String) async throws -> [MediaCard] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let extensions = try jsonString(ExtensionsPayload())
        let variables = try jsonString(Variables(query: trimmed))
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
            let response = try await client.decode(SearchResponse.self, from: endpoint)
            if response.data == nil, !(response.errors?.isEmpty ?? true) {
                throw PlaybackFailure.apiChanged
            }
            return response.cards.compactMap(MediaCard.init(dto:))
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

private struct SearchResponse: Decodable, Sendable {
    let data: SearchData?
    let errors: [GraphQLError]?

    var cards: [SearchCardDTO] {
        let containers = data?.getSearchPage?
            .areaContainersConnection?.areaContainers ?? []
        return containers.flatMap { container in
            (container.areas ?? []).flatMap { area in
                (area.sections ?? []).flatMap { section in
                    (section.collections ?? []).flatMap { collection in
                        collection.itemsConnection?.items ?? []
                    }
                }
            }
        }
    }
}

private struct GraphQLError: Decodable, Sendable {
    let message: String?
}

private struct SearchData: Decodable, Sendable {
    let getSearchPage: SearchPage?
}

private struct SearchPage: Decodable, Sendable {
    let areaContainersConnection: AreaContainersConnection?
}

private struct AreaContainersConnection: Decodable, Sendable {
    let areaContainers: [AreaContainer]?
}

private struct AreaContainer: Decodable, Sendable {
    let areas: [SearchArea]?
}

private struct SearchArea: Decodable, Sendable {
    let sections: [SearchSection]?
}

private struct SearchSection: Decodable, Sendable {
    let collections: [SearchCollection]?
}

private struct SearchCollection: Decodable, Sendable {
    let itemsConnection: SearchItemsConnection?
}

private struct SearchItemsConnection: Decodable, Sendable {
    let items: [SearchCardDTO]?
}

private struct SearchCardDTO: Decodable, Sendable {
    struct ImageDTO: Decodable, Sendable {
        let id: String?
        let r: String?
    }

    struct LinkDTO: Decodable, Sendable {
        let referenceId: String?
        let referenceType: String?
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

private extension MediaCard {
    init?(dto: SearchCardDTO) {
        guard let link = dto.cardLink?.value,
              let pageURL = URL(string: link),
              pageURL.scheme == "https",
              dto.cardLink?.referenceType?.lowercased() == "video" || pageURL.path.contains("/player/") else {
            return nil
        }
        let fallbackID = pageURL.absoluteString
        id = dto.cardLink?.referenceId ?? fallbackID
        title = dto.cardTitle?.nilIfBlank ?? "Contenido Mitele"
        subtitle = dto.cardEditorialMetadata?.nilIfBlank ?? dto.cardText?.nilIfBlank
        detail = dto.description?.nilIfBlank ?? dto.lastPublishDate?.nilIfBlank
        duration = dto.durationString?.nilIfBlank
        artworkURL = Self.artworkURL(from: dto.cardImages?.first)
        self.pageURL = pageURL
    }

    static func artworkURL(from image: SearchCardDTO.ImageDTO?) -> URL? {
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
