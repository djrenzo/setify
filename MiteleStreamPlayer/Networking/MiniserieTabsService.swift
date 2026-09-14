import Foundation

protocol MiniserieTabsFetching: Sendable {
    func fetchTab(targetURL: String, tag: String, page: Int, size: Int) async throws -> NumberedPage<MiniserieEpisode>
}

/// The legacy bitban "tabs" proxy used for miniseries episode trees — a flat/grouped node list
/// (grouping nodes wrap a season's episodes as `children`) with pagination that only appears as
/// `"actualPage":N,"totalPages":M` inside the raw response text, not a clean JSON field.
/// See API_STREAM_RESOLUTION.md §15.2.
struct MiniserieTabsService: MiniserieTabsFetching, Sendable {
    let client: HTTPClient

    func fetchTab(targetURL: String, tag: String, page: Int, size: Int) async throws -> NumberedPage<MiniserieEpisode> {
        let eid = "/tabs/mtweb?url=\(targetURL)&tabId=\(tag)&page=\(page)&size=\(size)"
        let url = try APIURL.mabURL(oid: "bitban", eid: eid)
        let endpoint = Endpoint(url: url, headers: APIConfiguration.scrapeHeaders)
        do {
            let data = try await client.data(for: endpoint)
            let response = try JSONDecoder().decode(TabsResponse.self, from: data)
            let episodes = flatten(response.contents ?? [])
            let text = String(data: data, encoding: .utf8) ?? ""
            let (actualPage, totalPages) = extractPagination(from: text, fallbackPage: page)
            return NumberedPage(items: episodes, currentPage: actualPage, totalPages: totalPages)
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        } catch is DecodingError {
            throw PlaybackFailure.apiChanged
        }
    }

    private func flatten(_ nodes: [TabNode], seasonTitle: String? = nil) -> [MiniserieEpisode] {
        var results: [MiniserieEpisode] = []
        for node in nodes {
            if let children = node.children, !children.isEmpty {
                let groupTitle = node.title.map { $0.replacingOccurrences(of: "\\", with: "") }
                results.append(contentsOf: flatten(children, seasonTitle: groupTitle))
            } else if let episode = MiniserieEpisode(node: node, seasonTitle: seasonTitle) {
                results.append(episode)
            }
        }
        return results
    }

    private func extractPagination(from text: String, fallbackPage: Int) -> (Int, Int) {
        guard let regex = try? NSRegularExpression(pattern: "\"actualPage\":(\\d+),\"totalPages\":(\\d+)"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let actualRange = Range(match.range(at: 1), in: text),
              let totalRange = Range(match.range(at: 2), in: text),
              let actual = Int(text[actualRange]),
              let total = Int(text[totalRange]) else {
            return (fallbackPage, fallbackPage)
        }
        return (actual, total)
    }
}

private struct TabsResponse: Decodable, Sendable {
    let contents: [TabNode]?
}

private struct TabNode: Decodable, Sendable {
    struct Info: Decodable, Sendable { let synopsis: String? }
    struct Link: Decodable, Sendable { let href: String? }
    struct Thumbnail: Decodable, Sendable { let src: String? }
    struct Images: Decodable, Sendable { let thumbnail: Thumbnail? }

    let title: String?
    let subtitle: String?
    let info: Info?
    let link: Link?
    let images: Images?
    let children: [TabNode]?
}

private func isSeasonPlaceholder(_ title: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: "^Temporada \\d+") else { return false }
    return regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
}

private extension MiniserieEpisode {
    init?(node: TabNode, seasonTitle: String?) {
        guard let rawHref = node.link?.href, !rawHref.isEmpty else { return nil }
        let href = rawHref.replacingOccurrences(of: "\\", with: "")
        let rawTitle = (node.title ?? "").replacingOccurrences(of: "\\", with: "")
        if node.children?.isEmpty ?? true, isSeasonPlaceholder(rawTitle) {
            return nil
        }
        guard let pageURL = URL(string: "https://www.mitele.es\(href)") else { return nil }

        id = pageURL.absoluteString
        self.seasonTitle = seasonTitle
        title = rawTitle.isEmpty ? "Episodio" : rawTitle

        let rawSubtitle = node.subtitle.map { $0.replacingOccurrences(of: "\\", with: "") }
        subtitle = (rawSubtitle?.isEmpty ?? true) ? nil : rawSubtitle

        let rawSynopsis = node.info?.synopsis.map { $0.replacingOccurrences(of: "\\", with: "") }
        overview = (rawSynopsis?.isEmpty ?? true) ? nil : rawSynopsis

        if let src = node.images?.thumbnail?.src?.replacingOccurrences(of: "\\", with: ""), !src.isEmpty {
            thumbnailURL = URL(string: src)
        } else {
            thumbnailURL = nil
        }
        self.pageURL = pageURL
    }
}
