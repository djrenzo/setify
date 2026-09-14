import Foundation

protocol SeriesPageFetching: Sendable {
    func seasons(refID: String) async throws -> [Season]
    func collections(seasonID: String) async throws -> [EpisodeCollection]
}

/// Wraps the "series page" persisted GraphQL query (`0cda6aecb...6b9eb4`, `MPlaySeriesPage`),
/// called once with a show's ref_id for seasons and again with a season's id for collections.
/// See API_STREAM_RESOLUTION.md §14.
struct SeriesPageService: SeriesPageFetching, Sendable {
    private struct ClientLibrary: Encodable {
        let name = "apollo-ios"
        let version = "1.24.0"
    }

    private struct PersistedQuery: Encodable {
        let sha256Hash = "0cda6aecb759eed86ae38200c0ba3caabf0a1f7e0fa5197471fc62612e6b9eb4"
        let version = 1
    }

    private struct ExtensionsPayload: Encodable {
        let clientLibrary = ClientLibrary()
        let persistedQuery = PersistedQuery()
    }

    private struct Variables: Encodable {
        let id: String
        let metadataTemplateName = "series-metadata-prod"
        let templateName = "series-page-prod"
    }

    let client: HTTPClient

    func seasons(refID: String) async throws -> [Season] {
        let page = try await fetchPage(refID: refID)
        let seasons = page.data?.getSeriesPage?.dataSource?.seasons ?? []
        return seasons.compactMap(Season.init(dto:))
    }

    func collections(seasonID: String) async throws -> [EpisodeCollection] {
        let page = try await fetchPage(refID: seasonID)
        let containers = page.data?.getSeriesPage?.areaContainersConnection?.areaContainers ?? []
        // The real collections list can sit at any area-container index; scan for the first
        // one whose first collection has a non-empty title (some indices are decorative/empty).
        for container in containers {
            let collections = container.areas?.first?.sections?.first?.collections ?? []
            if let firstTitle = collections.first?.title?.nilIfBlank, !firstTitle.isEmpty {
                return collections.compactMap(EpisodeCollection.init(dto:))
            }
        }
        return []
    }

    private func fetchPage(refID: String) async throws -> SeriesPageResponse {
        let extensions = try jsonString(ExtensionsPayload())
        let variables = try jsonString(Variables(id: refID))
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
            let response = try await client.decode(SeriesPageResponse.self, from: endpoint)
            if response.data == nil, !(response.errors?.isEmpty ?? true) {
                throw PlaybackFailure.apiChanged
            }
            return response
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

private struct SeriesPageResponse: Decodable, Sendable {
    let data: SeriesPageData?
    let errors: [SeriesPageError]?
}

private struct SeriesPageError: Decodable, Sendable {
    let message: String?
}

private struct SeriesPageData: Decodable, Sendable {
    let getSeriesPage: SeriesPageDTO?
}

private struct SeriesPageDTO: Decodable, Sendable {
    let dataSource: DataSourceDTO?
    let areaContainersConnection: AreaContainersConnectionDTO?
}

private struct DataSourceDTO: Decodable, Sendable {
    let seasons: [SeasonDTO]?
}

private struct SeasonDTO: Decodable, Sendable {
    struct LinkDTO: Decodable, Sendable { let referenceId: String? }
    let seasonTitle: String?
    let cardLink: LinkDTO?
}

private struct AreaContainersConnectionDTO: Decodable, Sendable {
    let areaContainers: [AreaContainerDTO]?
}

private struct AreaContainerDTO: Decodable, Sendable {
    let areas: [AreaDTO]?
}

private struct AreaDTO: Decodable, Sendable {
    let sections: [SectionDTO]?
}

private struct SectionDTO: Decodable, Sendable {
    let collections: [CollectionDTO]?
}

private struct CollectionDTO: Decodable, Sendable {
    let id: String?
    let title: String?
}

private extension Season {
    init?(dto: SeasonDTO) {
        guard let id = dto.cardLink?.referenceId?.nilIfBlank else { return nil }
        self.id = id
        title = dto.seasonTitle?.nilIfBlank ?? "Temporada"
    }
}

private extension EpisodeCollection {
    init?(dto: CollectionDTO) {
        guard let id = dto.id?.nilIfBlank else { return nil }
        self.id = id
        title = dto.title?.nilIfBlank ?? "Episodios"
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
