import SwiftUI

@MainActor
struct AtresEpisodesListView: View {
    let title: String
    let model: AppModel

    @State private var store: AtresEpisodesStore

    init(show: ShowSummary, season: Season, model: AppModel) {
        self.title = season.title
        self.model = model
        _store = State(initialValue: AtresEpisodesStore(
            service: model.catalog.atresFormatPage,
            formatID: show.id.strippingAtresPrefix,
            seasonID: season.id
        ))
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
