import Foundation
import Observation

@MainActor
@Observable
final class ShowCatalogStore {
    private let service: any ShowCatalogFetching
    private let refID: String
    private var cursor: String?
    private var hasNextPage = true
    private var task: Task<Void, Never>?

    var shows: [ShowSummary] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any ShowCatalogFetching, refID: String) {
        self.service = service
        self.refID = refID
    }

    func loadInitial() {
        guard shows.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard hasNextPage, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.fetchShows(refID: refID, after: cursor)
                try Task.checkCancellation()
                shows.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasNextPage = page.nextCursor != nil
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
}

@MainActor
@Observable
final class EpisodeCatalogStore {
    private let service: any EpisodeCatalogFetching
    private let collectionID: String
    private var cursor: String?
    private var hasNextPage = true
    private var task: Task<Void, Never>?

    var episodes: [MediaCard] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any EpisodeCatalogFetching, collectionID: String) {
        self.service = service
        self.collectionID = collectionID
    }

    func loadInitial() {
        guard episodes.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard hasNextPage, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.fetchEpisodes(collectionID: collectionID, after: cursor)
                try Task.checkCancellation()
                episodes.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasNextPage = page.nextCursor != nil
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
}

@MainActor
@Observable
final class SeasonsStore {
    private let service: any SeriesPageFetching
    private let refID: String
    private var task: Task<Void, Never>?

    var seasons: [Season] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any SeriesPageFetching, refID: String) {
        self.service = service
        self.refID = refID
    }

    func load() {
        guard seasons.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.seasons(refID: refID)
                try Task.checkCancellation()
                seasons = result
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
}

@MainActor
@Observable
final class CollectionsStore {
    private let service: any SeriesPageFetching
    private let seasonID: String
    private var task: Task<Void, Never>?

    var collections: [EpisodeCollection] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any SeriesPageFetching, seasonID: String) {
        self.service = service
        self.seasonID = seasonID
    }

    func load() {
        guard collections.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.collections(seasonID: seasonID)
                try Task.checkCancellation()
                collections = result
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
}
