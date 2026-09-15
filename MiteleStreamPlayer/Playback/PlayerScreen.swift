import AVKit
import SwiftUI

@MainActor
struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: PlayerSession
    @State private var isLandscape = true
    @State private var showsOverlay = true
    @State private var hideTask: Task<Void, Never>?

    init(stream: ResolvedStream, progressStore: WatchProgressStore) {
        _session = State(initialValue: PlayerSession(stream: stream, progressStore: progressStore))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerControllerView(player: session.player, onTap: toggleOverlay)
                .ignoresSafeArea()
            statusOverlay
            subtitleOverlay
            if showsOverlay {
                topBar.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsOverlay)
        .statusBarHidden()
        .onAppear {
            session.start()
            OrientationController.apply(.landscape)
            scheduleOverlayHide()
        }
        .onDisappear {
            session.stop()
            hideTask?.cancel()
            OrientationController.apply(.allButUpsideDown)
        }
    }

    @ViewBuilder
    private var subtitleOverlay: some View {
        if session.subtitlesEnabled, let text = session.subtitleText {
            VStack {
                Spacer()
                Text(text)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.65), in: .rect(cornerRadius: 6))
                    .padding(.horizontal, 32)
                    .padding(.bottom, isLandscape ? 30 : 90)
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if session.isLoading {
            VStack {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(session.isUsingFallback ? "Reintentando la señal…" : "Cargando vídeo…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(22)
            .background(.black.opacity(0.65), in: .rect(cornerRadius: 18))
        } else if let failure = session.failure {
            PlayerFailureView(failure: failure, onClose: close)
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Spacer()
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: .capsule)
                Spacer()
                HStack(spacing: 10) {
                    Button(action: toggleOrientation) {
                        Image(systemName: isLandscape ? "iphone" : "iphone.landscape")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.55), in: .circle)
                    }
                    .accessibilityLabel(isLandscape ? "Cambiar a vertical" : "Cambiar a horizontal")

                    if session.hasSubtitles {
                        Button(action: session.toggleSubtitles) {
                            Image(systemName: session.subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble")
                                .font(.headline)
                                .frame(width: 42, height: 42)
                                .background(.black.opacity(0.55), in: .circle)
                        }
                        .accessibilityLabel(session.subtitlesEnabled ? "Desactivar subtítulos" : "Activar subtítulos")
                    }
                }
            }
            .foregroundStyle(.white)
            .padding()
            Spacer()
        }
    }

    private func close() {
        session.stop()
        dismiss()
    }

    private func toggleOrientation() {
        isLandscape.toggle()
        OrientationController.apply(isLandscape ? .landscape : .portrait)
    }

    private func toggleOverlay() {
        showsOverlay.toggle()
        if showsOverlay {
            scheduleOverlayHide()
        } else {
            hideTask?.cancel()
        }
    }

    private func scheduleOverlayHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            showsOverlay = false
        }
    }
}

private struct PlayerFailureView: View {
    let failure: PlaybackFailure
    let onClose: () -> Void

    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.cinemaAccent)
            Text(failure.title)
                .font(.title3.bold())
            Text(failure.message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Cerrar", action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(Color.cinemaAccent)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 340)
        .background(Color.cinemaSurface.opacity(0.96), in: .rect(cornerRadius: 24))
    }
}

private struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.updatesNowPlayingInfoCenter = false

        // Added directly to AVPlayerViewController's own view (rather than as a separate SwiftUI
        // overlay gesture) so it observes the same taps AVKit uses to show/hide its native
        // controls, instead of competing with them for the touch.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        controller.view.addGestureRecognizer(tap)

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
