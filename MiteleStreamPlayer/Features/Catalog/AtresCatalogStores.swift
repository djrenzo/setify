import Foundation
import Observation

@MainActor
@Observable
final class AtresShowCatalogStore {
    private let service: any AtresRowFetching
    private let baseURL: URL
    private var nextPage: Int? = 0

    var shows: [ShowSummary] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any AtresRowFetching, baseURL: URL) {
        self.service = service
        self.baseURL = baseURL
    }

    func loadInitial() {
        guard shows.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard let page = nextPage, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.fetchFormats(baseURL: baseURL, page: page)
                try Task.checkCancellation()
                shows.append(contentsOf: result.items)
                nextPage = result.nextPage
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
final class AtresRecordingCatalogStore {
    private let service: any AtresRowFetching
    private let baseURL: URL
    private var nextPage: Int? = 0

    var items: [FlatCatalogItem] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any AtresRowFetching, baseURL: URL) {
        self.service = service
        self.baseURL = baseURL
    }

    func loadInitial() {
        guard items.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard let page = nextPage, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.fetchRecordings(baseURL: baseURL, page: page)
                try Task.checkCancellation()
                items.append(contentsOf: result.items)
                nextPage = result.nextPage
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
final class AtresSeasonsStore {
    private let service: any AtresFormatPageFetching
    private let formatID: String

    var seasons: [Season] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any AtresFormatPageFetching, formatID: String) {
        self.service = service
        self.formatID = formatID
    }

    func load() {
        guard seasons.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.fetchSeasons(formatID: formatID)
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
final class AtresEpisodesStore {
    private let service: any AtresFormatPageFetching
    private let formatID: String
    private let seasonID: String
    private var nextPage: Int? = 0

    var episodes: [MediaCard] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any AtresFormatPageFetching, formatID: String, seasonID: String) {
        self.service = service
        self.formatID = formatID
        self.seasonID = seasonID
    }

    func loadInitial() {
        guard episodes.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard let page = nextPage, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.fetchEpisodes(formatID: formatID, seasonID: seasonID, page: page)
                try Task.checkCancellation()
                episodes.append(contentsOf: result.items)
                nextPage = result.nextPage
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
