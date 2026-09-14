import Foundation

struct EditorialEntry: Sendable {
    let id: String
    let title: String
    let imageSrc: String?
    let imageHref: String?
}

protocol EditorialIndexFetching: Sendable {
    func fetchIndex(targetURL: String, page: Int, size: Int) async throws -> NumberedPage<EditorialEntry>
}

/// The legacy bitban "automaticIndex" proxy (mab.mediaset.es) used for Series, Miniseries and
/// Películas/Documentales catalogs — a plain unauthenticated scrape, page-number paginated.
/// See API_STREAM_RESOLUTION.md §5, §13.1, §15.1, §16.
struct BitbanEditorialIndexService: EditorialIndexFetching, Sendable {
    let client: HTTPClient

    func fetchIndex(targetURL: String, page: Int, size: Int) async throws -> NumberedPage<EditorialEntry> {
        let eid = "/automaticIndex/mtweb?url=\(targetURL)&page=\(page)&id=a-z&size=\(size)"
        let url = try APIURL.mabURL(oid: "bitban", eid: eid)
        let endpoint = Endpoint(url: url, headers: APIConfiguration.scrapeHeaders)
        do {
            let response = try await client.decode(EditorialIndexResponse.self, from: endpoint)
            let items = (response.editorialObjects ?? []).compactMap(EditorialEntry.init(dto:))
            let actualPage = response.pagination?.actualPage ?? page
            let totalPages = response.pagination?.totalPages ?? actualPage
            return NumberedPage(items: items, currentPage: actualPage, totalPages: totalPages)
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
    }
}

private struct EditorialIndexResponse: Decodable, Sendable {
    struct Pagination: Decodable, Sendable {
        let actualPage: Int?
        let totalPages: Int?
    }

    struct Image: Decodable, Sendable {
        let src: String?
        let href: String?
    }

    struct Entry: Decodable, Sendable {
        let id: String?
        let title: String?
        let image: Image?
    }

    let editorialObjects: [Entry]?
    let pagination: Pagination?
}

private extension EditorialEntry {
    init?(dto: EditorialIndexResponse.Entry) {
        guard let id = dto.id?.nilIfBlank, let title = dto.title?.nilIfBlank else { return nil }
        self.id = id
        self.title = title
        imageSrc = dto.image?.src?.nilIfBlank
        imageHref = dto.image?.href?.nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
