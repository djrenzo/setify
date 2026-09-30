import AVKit
import SwiftUI
import UIKit

@MainActor
struct PlayerScreen: View {
    /// Owned by `PlaybackCoordinator`, which starts/stops it — this screen is only one of its
    /// views, alongside the Now Playing bar, so dismissing it doesn't end playback.
    let session: PlayerSession
    let onMinimize: () -> Void
    let onClose: () -> Void

    @State private var isLandscape = true
    @State private var showsOverlay = true
    @State private var hideTask: Task<Void, Never>?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerControllerView(
                session: session,
                onTap: toggleOverlay,
                onDragChanged: dragChanged,
                onDragEnded: dragEnded
            )
            .ignoresSafeArea()
            statusOverlay
            subtitleOverlay
            if showsOverlay {
                topBar.transition(.opacity)
            }
        }
        .offset(y: dragOffset)
        .animation(.easeInOut(duration: 0.2), value: showsOverlay)
        .presentationBackground(.clear)
        .statusBarHidden()
        .onAppear {
            OrientationController.apply(isLandscape ? .landscape : .portrait)
            scheduleOverlayHide()
        }
        .onDisappear {
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
                Button(action: onMinimize) {
                    Image(systemName: "chevron.down")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.55), in: .circle)
                }
                .accessibilityLabel("Minimizar reproductor")
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
        onClose()
    }

    private func dragChanged(_ translation: CGFloat) {
        dragOffset = max(translation, 0)
    }

    /// Swiping down far or fast enough minimizes into the Now Playing bar; otherwise the player
    /// springs back into place.
    private func dragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        if translation > 140 || velocity > 900 {
            onMinimize()
        } else {
            withAnimation(.spring(duration: 0.3)) {
                dragOffset = 0
            }
        }
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

    @State private var showsDiagnostics = false

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
            HStack {
                if !DiagnosticsLog.shared.isEmpty {
                    Button("Diagnóstico") { showsDiagnostics = true }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
                Button("Cerrar", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cinemaAccent)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 340)
        .background(Color.cinemaSurface.opacity(0.96), in: .rect(cornerRadius: 24))
        .sheet(isPresented: $showsDiagnostics) {
            DiagnosticsView(log: DiagnosticsLog.shared)
        }
    }
}

/// Read-only view of the captured FairPlay trace with a one-tap copy — shown from a DRM playback
/// failure so the log can be pasted into a report without attaching Xcode.
private struct DiagnosticsView: View {
    let log: DiagnosticsLog
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(log.text.isEmpty ? "Sin registros." : log.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Diagnóstico FairPlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(didCopy ? "Copiado" : "Copiar") {
                        UIPasteboard.general.string = log.text
                        didCopy = true
                    }
                }
            }
        }
    }
}

private struct PlayerControllerView: UIViewControllerRepresentable {
    let session: PlayerSession
    let onTap: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onTap: onTap, onDragChanged: onDragChanged, onDragEnded: onDragEnded)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        session.attachVideoSurface(controller)
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

        // Swipe down to minimize into the Now Playing bar. Only begins on a predominantly
        // downward drag (see `gestureRecognizerShouldBegin`), so AVKit's horizontal scrubbing
        // and other controls are unaffected.
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        controller.view.addGestureRecognizer(pan)

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if context.coordinator.session !== session {
            context.coordinator.session.detachVideoSurface(controller)
            context.coordinator.session = session
        }
        session.attachVideoSurface(controller)
        context.coordinator.onTap = onTap
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.session.detachVideoSurface(controller)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var session: PlayerSession
        var onTap: () -> Void
        var onDragChanged: (CGFloat) -> Void
        var onDragEnded: (CGFloat, CGFloat) -> Void

        init(
            session: PlayerSession,
            onTap: @escaping () -> Void,
            onDragChanged: @escaping (CGFloat) -> Void,
            onDragEnded: @escaping (CGFloat, CGFloat) -> Void
        ) {
            self.session = session
            self.onTap = onTap
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
        }

        @objc func handleTap() {
            onTap()
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            let translation = pan.translation(in: pan.view).y
            switch pan.state {
            case .changed:
                onDragChanged(translation)
            case .ended:
                onDragEnded(translation, pan.velocity(in: pan.view).y)
            case .cancelled, .failed:
                onDragEnded(0, 0)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return velocity.y > 0 && abs(velocity.y) > abs(velocity.x) * 1.5
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
