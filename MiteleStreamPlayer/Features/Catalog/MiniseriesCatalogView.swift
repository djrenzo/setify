import SwiftUI

struct MiniserieRoute: Hashable {
    let show: MiniserieShow
}

@MainActor
struct MiniseriesCatalogView: View {
    @State var store: MiniseriesCatalogStore
    let model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.shows) { show in
                    NavigationLink(value: MiniserieRoute(show: show)) {
                        MiniserieTile(
                            show: show,
                            isFavorite: model.favorites.isFavorite(FavoriteItem(miniserie: show).id)
                        ) {
                            Task { await model.favorites.toggle(FavoriteItem(miniserie: show)) }
                        }
                    }
                    .buttonStyle(.plain)
                    .task {
                        if show.id == store.shows.last?.id {
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
            if let message = store.errorMessage, store.shows.isEmpty {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(message))
                    .padding(.top, 60)
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle("Miniseries")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MiniserieRoute.self) { route in
            MiniserieEpisodesView(show: route.show, model: model)
        }
        .task { store.loadInitial() }
    }
}

private struct MiniserieTile: View {
    let show: MiniserieShow
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SquarePosterImage(url: show.posterURL)
                .overlay(alignment: .topTrailing) {
                    FavoriteHeartButton(isFavorite: isFavorite, onToggle: onToggleFavorite)
                }
            Text(show.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
        }
    }
}
