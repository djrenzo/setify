import SwiftUI

@MainActor
struct PeliculasCatalogView: View {
    @State var store: PeliculasCatalogStore
    let model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.items) { item in
                    Button {
                        model.playback.prepare(.video(mediaCard(for: item)))
                    } label: {
                        PeliculaTile(
                            item: item,
                            isFavorite: model.favorites.isFavorite(FavoriteItem(pelicula: item).id),
                            watchedFraction: model.watchProgress.fraction(for: item.id),
                            downloadState: model.downloads.state(for: item.id),
                            onDownloadTap: { handleDownloadTap(item) }
                        ) {
                            Task { await model.favorites.toggle(FavoriteItem(pelicula: item)) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reproducir \(item.title)")
                    .task {
                        if item.id == store.items.last?.id {
                            store.loadNextPage()
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            if store.isLoading {
                ProgressView().padding()
            }
            if let message = store.errorMessage, store.items.isEmpty {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(message))
                    .padding(.top, 60)
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle("Películas")
        .navigationBarTitleDisplayMode(.inline)
        .task { store.loadInitial() }
        .task { await model.watchProgress.loadIfNeeded() }
        .task { await model.downloads.loadIfNeeded() }
    }

    private func mediaCard(for item: FlatCatalogItem) -> MediaCard {
        MediaCard(
            id: item.id,
            title: item.title,
            subtitle: nil,
            detail: nil,
            duration: nil,
            artworkURL: item.posterURL,
            pageURL: item.pageURL
        )
    }

    private func handleDownloadTap(_ item: FlatCatalogItem) {
        switch model.downloads.state(for: item.id) {
        case .notDownloaded, .failed:
            model.downloads.startDownload(card: mediaCard(for: item))
        case .downloading:
            model.downloads.cancelDownload(contentID: item.id)
        case .downloaded:
            Task { await model.downloads.delete(contentID: item.id) }
        }
    }
}

private struct PeliculaTile: View {
    let item: FlatCatalogItem
    let isFavorite: Bool
    let watchedFraction: Double
    let downloadState: DownloadState
    let onDownloadTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SquarePosterImage(url: item.posterURL)
                .overlay(alignment: .topTrailing) {
                    FavoriteHeartButton(isFavorite: isFavorite, onToggle: onToggleFavorite)
                }
                .overlay(alignment: .topLeading) {
                    DownloadButton(state: downloadState, onTap: onDownloadTap)
                        .padding(6)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .overlay(alignment: .bottom) {
                    WatchProgressBar(fraction: watchedFraction)
                }
            Text(item.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
        }
    }
}
