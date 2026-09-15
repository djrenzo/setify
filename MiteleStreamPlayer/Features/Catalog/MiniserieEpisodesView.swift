import SwiftUI

@MainActor
struct MiniserieEpisodesView: View {
    let show: MiniserieShow
    let model: AppModel

    @State private var store: MiniserieEpisodesStore

    init(show: MiniserieShow, model: AppModel) {
        self.show = show
        self.model = model
        _store = State(initialValue: MiniserieEpisodesStore(
            service: model.catalog.miniserieTabs,
            targetURL: show.pageURL.absoluteString,
            tag: show.tag
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(store.episodes) { episode in
                    MiniserieEpisodeRow(
                        episode: episode,
                        watchedFraction: model.watchProgress.fraction(for: episode.id),
                        downloadState: model.downloads.state(for: episode.id),
                        onDownloadTap: { handleDownloadTap(episode) }
                    ) {
                        model.playback.prepare(.video(mediaCard(for: episode)))
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
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { store.loadInitial() }
        .task { await model.watchProgress.loadIfNeeded() }
        .task { await model.downloads.loadIfNeeded() }
    }

    private func mediaCard(for episode: MiniserieEpisode) -> MediaCard {
        MediaCard(
            id: episode.id,
            title: episode.title,
            subtitle: episode.subtitle,
            detail: episode.overview,
            duration: nil,
            artworkURL: episode.thumbnailURL,
            pageURL: episode.pageURL
        )
    }

    private func handleDownloadTap(_ episode: MiniserieEpisode) {
        switch model.downloads.state(for: episode.id) {
        case .notDownloaded, .failed:
            model.downloads.startDownload(card: mediaCard(for: episode))
        case .downloading:
            model.downloads.cancelDownload(contentID: episode.id)
        case .downloaded:
            Task { await model.downloads.delete(contentID: episode.id) }
        }
    }
}

private struct MiniserieEpisodeRow: View {
    let episode: MiniserieEpisode
    let watchedFraction: Double
    let downloadState: DownloadState
    let onDownloadTap: () -> Void
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    if let seasonTitle = episode.seasonTitle {
                        Text(seasonTitle.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(Color.cinemaAccent)
                    }
                    Text(episode.title).font(.headline).lineLimit(2)
                    if let subtitle = episode.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
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
        .accessibilityLabel("Reproducir \(episode.title)")
    }

    private var artwork: some View {
        AsyncImage(url: episode.thumbnailURL) { phase in
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
