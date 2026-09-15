import SwiftUI

@MainActor
struct PeliculasCatalogView: View {
    @State var store: PeliculasCatalogStore
    @State var atresStore: AtresRecordingCatalogStore
    let model: AppModel

    @State private var source = PlatformSource.mitele

    var body: some View {
        VStack(spacing: 0) {
            PlatformSourcePicker(selection: $source)
            switch source {
            case .mitele:
                grid(
                    items: store.items,
                    isLoading: store.isLoading,
                    errorMessage: store.errorMessage,
                    favoriteKind: .pelicula,
                    onReachEnd: store.loadNextPage
                )
                .task { store.loadInitial() }
            case .atresplayer:
                grid(
                    items: atresStore.items,
                    isLoading: atresStore.isLoading,
                    errorMessage: atresStore.errorMessage,
                    favoriteKind: .atresPelicula,
                    onReachEnd: atresStore.loadNextPage
                )
                .task { atresStore.loadInitial() }
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle("Películas")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.watchProgress.loadIfNeeded() }
        .task { await model.downloads.loadIfNeeded() }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private func grid(
        items: [FlatCatalogItem],
        isLoading: Bool,
        errorMessage: String?,
        favoriteKind: FavoriteKind,
        onReachEnd: @escaping () -> Void
    ) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    Button {
                        model.playback.prepare(.video(mediaCard(for: item)))
                    } label: {
                        PeliculaTile(
                            item: item,
                            isFavorite: model.favorites.isFavorite(FavoriteItem(pelicula: item, kind: favoriteKind).id),
                            watchedFraction: model.watchProgress.fraction(for: item.id),
                            downloadState: model.downloads.state(for: item.id),
                            onDownloadTap: { handleDownloadTap(item) }
                        ) {
                            Task { await model.favorites.toggle(FavoriteItem(pelicula: item, kind: favoriteKind)) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reproducir \(item.title)")
                    .task {
                        if item.id == items.last?.id {
                            onReachEnd()
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            if isLoading {
                ProgressView().padding()
            }
            if let errorMessage, items.isEmpty {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                    .padding(.top, 60)
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
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
