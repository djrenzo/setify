import Foundation
import Observation

@MainActor
@Observable
final class SearchStore {
    private let service: any MediaSearching
    private var task: Task<Void, Never>?

    var query = ""
    var results: [MediaCard] = []
    var isLoading = false
    var hasSearched = false
    var errorMessage: String?

    init(service: any MediaSearching) {
        self.service = service
    }

    func submit() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        guard !value.isEmpty else {
            results = []
            hasSearched = false
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await service.search(query: value)
                try Task.checkCancellation()
                results = items
                hasSearched = true
                isLoading = false
            } catch is CancellationError {
                return
            } catch let failure as PlaybackFailure {
                results = []
                hasSearched = true
                isLoading = false
                errorMessage = failure.message
            } catch {
                results = []
                hasSearched = true
                isLoading = false
                errorMessage = PlaybackFailure.network.message
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }
}
