import Foundation
import Observation

enum CatalogTarget {
    static let seriesIndexURL = "https://www.mitele.es/series-online/"
    static let miniseriesIndexURL = "https://www.mitele.es/miniseries/"
    static let peliculasIndexURL = "https://www.mitele.es/peliculas/"
}

/// Legacy `id` values from the editorial index aren't valid GraphQL ref_ids yet — they need a
/// zero-padded `MS` prefix. See API_STREAM_RESOLUTION.md §13.
private func normalizedSeriesRefID(_ rawID: String) -> String {
    switch rawID.count {
    case 6: "MS000000" + rawID
    case 7: "MS00000" + rawID
    default: rawID
    }
}

@MainActor
@Observable
final class SeriesCatalogStore {
    private let service: any EditorialIndexFetching
    private var nextPage = 1
    private var totalPages = 1
    private var task: Task<Void, Never>?

    var shows: [ShowSummary] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any EditorialIndexFetching) {
        self.service = service
    }

    private var canLoadMore: Bool { nextPage <= totalPages }

    func loadInitial() {
        guard shows.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.fetchIndex(
                    targetURL: CatalogTarget.seriesIndexURL,
                    page: nextPage,
                    size: 100
                )
                try Task.checkCancellation()
                shows.append(contentsOf: page.items.map(Self.mapShow))
                totalPages = page.totalPages
                nextPage = page.currentPage + 1
                isLoading = false
            } catch is CancellationError {
            } catch let failure as PlaybackFailure {
                isLoading = false
                errorMessage = failure.message
            } catch {
                isLoading = false
                errorMessage = PlaybackFailure.network.message
            }
        }
    }

    private static func mapShow(_ entry: EditorialEntry) -> ShowSummary {
        ShowSummary(
            id: normalizedSeriesRefID(entry.id),
            title: entry.title,
            subtitle: nil,
            posterURL: entry.imageSrc.flatMap(URL.init(string:))
        )
    }
}

@MainActor
@Observable
final class MiniseriesCatalogStore {
    private let service: any EditorialIndexFetching
    private var nextPage = 1
    private var totalPages = 1
    private var task: Task<Void, Never>?

    var shows: [MiniserieShow] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any EditorialIndexFetching) {
        self.service = service
    }

    private var canLoadMore: Bool { nextPage <= totalPages }

    func loadInitial() {
        guard shows.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.fetchIndex(
                    targetURL: CatalogTarget.miniseriesIndexURL,
                    page: nextPage,
                    size: 24
                )
                try Task.checkCancellation()
                shows.append(contentsOf: page.items.map(Self.mapShow))
                totalPages = page.totalPages
                nextPage = page.currentPage + 1
                isLoading = false
            } catch is CancellationError {
            } catch let failure as PlaybackFailure {
                isLoading = false
                errorMessage = failure.message
            } catch {
                isLoading = false
                errorMessage = PlaybackFailure.network.message
            }
        }
    }

    private static func mapShow(_ entry: EditorialEntry) -> MiniserieShow {
        MiniserieShow(
            id: entry.id,
            tag: entry.id + ".0",
            title: entry.title,
            posterURL: entry.imageSrc.flatMap(URL.init(string:))
        )
    }
}

@MainActor
@Observable
final class PeliculasCatalogStore {
    private let service: any EditorialIndexFetching
    private var nextPage = 1
    private var totalPages = 1
    private var task: Task<Void, Never>?

    var items: [FlatCatalogItem] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any EditorialIndexFetching) {
        self.service = service
    }

    private var canLoadMore: Bool { nextPage <= totalPages }

    func loadInitial() {
        guard items.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.fetchIndex(
                    targetURL: CatalogTarget.peliculasIndexURL,
                    page: nextPage,
                    size: 24
                )
                try Task.checkCancellation()
                items.append(contentsOf: page.items.compactMap(Self.mapItem))
                totalPages = page.totalPages
                nextPage = page.currentPage + 1
                isLoading = false
            } catch is CancellationError {
            } catch let failure as PlaybackFailure {
                isLoading = false
                errorMessage = failure.message
            } catch {
                isLoading = false
                errorMessage = PlaybackFailure.network.message
            }
        }
    }

    private static func mapItem(_ entry: EditorialEntry) -> FlatCatalogItem? {
        guard let href = entry.imageHref, let pageURL = URL(string: "https://www.mitele.es\(href)") else {
            return nil
        }
        return FlatCatalogItem(
            id: entry.id,
            title: entry.title,
            posterURL: entry.imageSrc.flatMap(URL.init(string:)),
            pageURL: pageURL
        )
    }
}
