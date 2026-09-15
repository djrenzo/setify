import Foundation

/// Fans one query out to both platforms concurrently and merges whatever comes back. A failure
/// on one side degrades gracefully to just the other's results — only surfaced as an error when
/// both sides fail and there's genuinely nothing to show, so a brief Atresplayer hiccup doesn't
/// take down Mitele search (or vice versa).
struct CombinedSearchService: MediaSearching, Sendable {
    let mitele: any MediaSearching
    let atres: any MediaSearching

    func search(query: String) async throws -> [SearchResult] {
        async let miteleAttempt = Self.attemptSearch(mitele, query: query)
        async let atresAttempt = Self.attemptSearch(atres, query: query)
        let (miteleResult, atresResult) = await (miteleAttempt, atresAttempt)

        var combined: [SearchResult] = []
        var firstFailure: PlaybackFailure?
        for result in [miteleResult, atresResult] {
            switch result {
            case .success(let items): combined.append(contentsOf: items)
            case .failure(let failure): if firstFailure == nil { firstFailure = failure }
            }
        }
        if combined.isEmpty, let firstFailure {
            throw firstFailure
        }
        return combined
    }

    /// `Result`'s failure branch is pinned to the concrete, `Sendable` `PlaybackFailure` — both
    /// `MiteleSearchService` and `AtresSearchService` only ever throw that in practice, and a
    /// plain `any Error` wouldn't cross the `async let` boundary under strict concurrency.
    private static func attemptSearch(_ service: any MediaSearching, query: String) async -> Result<[SearchResult], PlaybackFailure> {
        do {
            return .success(try await service.search(query: query))
        } catch let failure as PlaybackFailure {
            return .failure(failure)
        } catch {
            return .failure(.network)
        }
    }
}
