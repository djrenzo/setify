import SwiftUI

struct DownloadButton: View {
    let state: DownloadState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            content
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.45), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        case .failed:
            Image(systemName: "arrow.clockwise.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.cinemaAccent)
        case .downloading(let progress):
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(progress, 0.04))
                    .stroke(Color.cinemaAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.cinemaAccent)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .notDownloaded: "Descargar"
        case .failed: "Reintentar descarga"
        case .downloading: "Cancelar descarga"
        case .downloaded: "Eliminar descarga"
        }
    }
}
