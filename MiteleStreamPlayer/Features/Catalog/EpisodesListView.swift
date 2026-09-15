import SwiftUI

@MainActor
struct EpisodesListView: View {
    let title: String
    let model: AppModel

    @State private var store: EpisodeCatalogStore

    init(title: String, collectionID: String, model: AppModel) {
        self.title = title
        self.model = model
        _store = State(initialValue: EpisodeCatalogStore(service: model.catalog.episodeCatalog, collectionID: collectionID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.episodes) { episode in
                    EpisodeRow(
                        card: episode,
                        watchedFraction: model.watchProgress.fraction(for: episode.id),
                        downloadState: model.downloads.state(for: episode.id),
                        onDownloadTap: { handleDownloadTap(episode) }
                    ) {
                        model.playback.prepare(.video(episode))
                    }
                    .task {
                        if episode.id == store.episodes.last?.id {
                            store.loadNextPage()
                        }
                    }
                }
            }
            .padding(18)
            if store.isLoading {
                ProgressView().padding()
            }
            if let message = store.errorMessage, store.episodes.isEmpty {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(message))
                    .padding(.top, 60)
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { store.loadInitial() }
        .task { await model.watchProgress.loadIfNeeded() }
        .task { await model.downloads.loadIfNeeded() }
    }

    private func handleDownloadTap(_ episode: MediaCard) {
        switch model.downloads.state(for: episode.id) {
        case .notDownloaded, .failed:
            model.downloads.startDownload(card: episode)
        case .downloading:
            model.downloads.cancelDownload(contentID: episode.id)
        case .downloaded:
            Task { await model.downloads.delete(contentID: episode.id) }
        }
    }
}

struct EpisodeRow: View {
    let card: MediaCard
    let watchedFraction: Double
    let downloadState: DownloadState
    let onDownloadTap: () -> Void
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title).font(.headline).lineLimit(2)
                    if let subtitle = card.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let duration = card.duration {
                        Label(duration, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                DownloadButton(state: downloadState, onTap: onDownloadTap)
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.cinemaAccent)
            }
            .padding(12)
            .contentShape(.rect)
            .cinemaCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reproducir \(card.title)")
    }

    private var artwork: some View {
        AsyncImage(url: card.artworkURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.cinemaSurfaceRaised
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 116, height: 72)
        .overlay(alignment: .bottom) {
            WatchProgressBar(fraction: watchedFraction)
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}
