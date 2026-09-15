import SwiftUI

@MainActor
struct DownloadsView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cinemaBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Descargas")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Color.cinemaAccent)
        .task { await model.downloads.loadIfNeeded() }
        .task { await model.watchProgress.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if model.downloads.downloads.isEmpty {
            ContentUnavailableView(
                "Sin descargas",
                systemImage: "arrow.down.circle",
                description: Text("Descarga episodios y películas desde su ficha para verlos sin conexión.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(sortedDownloads) { item in
                        DownloadedRow(
                            item: item,
                            watchedFraction: model.watchProgress.fraction(for: item.contentID),
                            onPlay: { play(item) },
                            onDelete: { Task { await model.downloads.delete(contentID: item.contentID) } }
                        )
                    }
                }
                .padding(18)
            }
        }
    }

    private var sortedDownloads: [DownloadedItem] {
        model.downloads.downloads.values.sorted { $0.downloadedAt > $1.downloadedAt }
    }

    private func play(_ item: DownloadedItem) {
        guard let stream = model.downloads.resolvedStream(for: item.contentID) else { return }
        model.playback.prepare(.downloaded(stream))
    }
}

private struct DownloadedRow: View {
    let item: DownloadedItem
    let watchedFraction: Double
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.headline).lineLimit(2)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Label("Disponible sin conexión", systemImage: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.cinemaAccent)
                }
                Spacer(minLength: 0)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Eliminar descarga")
            }
            .padding(12)
            .contentShape(.rect)
            .cinemaCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reproducir \(item.title)")
    }

    private var artwork: some View {
        SquarePosterImage(url: item.artworkURL)
            .frame(width: 72, height: 72)
            .overlay(alignment: .bottom) {
                WatchProgressBar(fraction: watchedFraction)
            }
    }
}
