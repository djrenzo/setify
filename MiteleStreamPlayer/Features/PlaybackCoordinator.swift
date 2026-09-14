import Foundation
import Observation

struct PresentedFailure: Identifiable {
    let id = UUID()
    let failure: PlaybackFailure
}

@MainActor
@Observable
final class PlaybackCoordinator {
    private let resolver: any StreamResolving
    private let identityService: GigyaIdentityService
    private var task: Task<Void, Never>?

    var phase: PreparationPhase?
    var stream: ResolvedStream?
    var presentedFailure: PresentedFailure?

    init(resolver: any StreamResolving, identityService: GigyaIdentityService) {
        self.resolver = resolver
        self.identityService = identityService
    }

    func prepare(_ request: PlaybackRequest) {
        task?.cancel()
        stream = nil
        presentedFailure = nil
        phase = .resolvingMetadata

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await resolver.resolve(request) { [weak self] nextPhase in
                    await self?.setPhase(nextPhase)
                }
                try Task.checkCancellation()
                stream = resolved
                phase = nil
            } catch is CancellationError {
                phase = nil
            } catch let failure as PlaybackFailure {
                phase = nil
                presentedFailure = PresentedFailure(failure: failure)
            } catch {
                phase = nil
                presentedFailure = PresentedFailure(failure: .network)
            }
        }
    }

    func cancelPreparation() {
        task?.cancel()
        task = nil
        phase = nil
    }

    func playerDismissed() {
        stream = nil
    }

    func invalidateIdentity() async {
        await identityService.invalidate()
    }

    private func setPhase(_ phase: PreparationPhase) {
        self.phase = phase
    }
}