import Foundation
import Observation

@MainActor
@Observable
final class MiniserieEpisodesStore {
    private let service: any MiniserieTabsFetching
    private let targetURL: String
    private let tag: String
    private var nextPage = 1
    private var totalPages = 1
    private var task: Task<Void, Never>?

    var episodes: [MiniserieEpisode] = []
    var isLoading = false
    var errorMessage: String?

    init(service: any MiniserieTabsFetching, targetURL: String, tag: String) {
        self.service = service
        self.targetURL = targetURL
        self.tag = tag
    }

    private var canLoadMore: Bool { nextPage <= totalPages }

    func loadInitial() {
        guard episodes.isEmpty, !isLoading else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.fetchTab(targetURL: targetURL, tag: tag, page: nextPage, size: 50)
                try Task.checkCancellation()
                episodes.append(contentsOf: page.items)
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
}
