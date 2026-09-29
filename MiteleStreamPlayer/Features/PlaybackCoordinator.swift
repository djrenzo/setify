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
    private let progressStore: WatchProgressStore
    private var task: Task<Void, Never>?
    private var clearsSessionOnDismiss = false

    var phase: PreparationPhase?
    var presentedFailure: PresentedFailure?
    /// The active playback, owned here rather than by `PlayerScreen` so it keeps playing after
    /// the fullscreen player is dismissed into the Now Playing bar.
    private(set) var session: PlayerSession?
    /// Whether the fullscreen player is presented; `false` with a live `session` means the
    /// Now Playing bar is showing instead.
    var isPlayerExpanded = false

    init(
        resolver: any StreamResolving,
        identityService: GigyaIdentityService,
        progressStore: WatchProgressStore
    ) {
        self.resolver = resolver
        self.identityService = identityService
        self.progressStore = progressStore
    }

    /// The current session (if any) keeps playing while the new request resolves, and is only
    /// replaced once the new stream is ready.
    func prepare(_ request: PlaybackRequest) {
        task?.cancel()
        presentedFailure = nil
        phase = .resolvingMetadata

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await resolver.resolve(request) { [weak self] nextPhase in
                    await self?.setPhase(nextPhase)
                }
                try Task.checkCancellation()
                phase = nil
                startSession(for: resolved)
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

    func minimizePlayer() {
        guard isPlayerExpanded else { return }
        session?.keepPlayingThroughTransition()
        isPlayerExpanded = false
    }

    func expandPlayer() {
        guard session != nil else { return }
        isPlayerExpanded = true
    }

    /// Stops playback immediately; if the fullscreen player is up, the session itself is only
    /// released once its dismissal finishes (`playerCoverDismissed`), so the cover doesn't go
    /// blank mid-animation.
    func closePlayer() {
        session?.stop()
        if isPlayerExpanded {
            clearsSessionOnDismiss = true
            isPlayerExpanded = false
        } else {
            session = nil
        }
    }

    /// Called however the fullscreen player went away — the minimize button/gesture, AVKit's own
    /// dismissal, or `closePlayer()`. Only the latter ends the session.
    func playerCoverDismissed() {
        if clearsSessionOnDismiss {
            clearsSessionOnDismiss = false
            session = nil
        } else {
            session?.keepPlayingThroughTransition()
        }
    }

    func invalidateIdentity() async {
        await identityService.invalidate()
    }

    private func startSession(for stream: ResolvedStream) {
        session?.stop()
        clearsSessionOnDismiss = false
        let newSession = PlayerSession(stream: stream, progressStore: progressStore)
        session = newSession
        newSession.start()
        isPlayerExpanded = true
    }

    private func setPhase(_ phase: PreparationPhase) {
        self.phase = phase
    }
}