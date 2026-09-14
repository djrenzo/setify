import AVKit
import SwiftUI

@MainActor
struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: PlayerSession

    init(stream: ResolvedStream) {
        _session = State(initialValue: PlayerSession(stream: stream))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerControllerView(player: session.player)
                .ignoresSafeArea()
            statusOverlay
            topBar
        }
        .statusBarHidden()
        .onAppear { session.start() }
        .onDisappear { session.stop() }
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
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.55), in: .circle)
                }
                .accessibilityLabel("Cerrar reproductor")
                Spacer()
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: .capsule)
                Spacer()
                Color.clear.frame(width: 42, height: 42)
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

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
