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
                    let favorite = FavoriteItem(pelicula: item)
                    ZStack(alignment: .topTrailing) {
                        Button {
                            model.playback.prepare(.video(MediaCard(
                                id: item.id,
                                title: item.title,
                                subtitle: nil,
                                detail: nil,
                                duration: nil,
                                artworkURL: item.posterURL,
                                pageURL: item.pageURL
                            )))
                        } label: {
                            PeliculaTile(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reproducir \(item.title)")
                        FavoriteHeartButton(isFavorite: model.favorites.isFavorite(favorite.id)) {
                            Task { await model.favorites.toggle(favorite) }
                        }
                    }
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
    }
}

private struct PeliculaTile: View {
    let item: FlatCatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artwork
            Text(item.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
        }
    }

    private var artwork: some View {
        AsyncImage(url: item.posterURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.cinemaSurfaceRaised
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .clipShape(.rect(cornerRadius: 14))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .padding(8)
        }
    }
}
