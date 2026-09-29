import SwiftUI

/// Mini player shown above the tab bar while a `PlayerSession` is alive but the fullscreen
/// player has been dismissed. Tapping it (or swiping it up) re-expands the player.
@MainActor
struct NowPlayingBar: View {
    let session: PlayerSession
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    statusLabel
                }
                Spacer(minLength: 0)
                Button(action: session.togglePlayPause) {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .disabled(session.failure != nil)
                .accessibilityLabel(session.isPlaying ? "Pausar" : "Reproducir")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 36, height: 40)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Cerrar reproductor")
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 8)

            if let progress = session.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.cinemaAccent)
                    .scaleEffect(x: 1, y: 0.6, anchor: .bottom)
            }
        }
        .foregroundStyle(.white)
        .background(Color.cinemaSurfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .contentShape(.rect)
        .onTapGesture(perform: onExpand)
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.height < -30 {
                    onExpand()
                }
            }
        )
        .accessibilityAction(named: "Abrir reproductor", onExpand)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = session.artworkImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: session.isLive ? "dot.radiowaves.left.and.right" : "play.rectangle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.cinemaSurface)
            }
        }
        .frame(width: 64, height: 36)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var statusLabel: some View {
        if session.failure != nil {
            Text("Error de reproducción")
                .font(.caption)
                .foregroundStyle(Color.cinemaAccent)
        } else if session.isLoading {
            Text("Cargando…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if session.isLive {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.cinemaAccent)
                    .frame(width: 6, height: 6)
                Text("EN DIRECTO")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.secondary)
        } else {
            Text(session.isPlaying ? "Reproduciendo" : "En pausa")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
