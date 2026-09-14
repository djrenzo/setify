import SwiftUI

@MainActor
struct FavoritesView: View {
    let model: AppModel

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.cinemaBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Favoritos")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ShowRoute.self) { route in
                ShowDetailView(show: route.show, model: model)
            }
            .navigationDestination(for: MiniserieRoute.self) { route in
                MiniserieEpisodesView(show: route.show, model: model)
            }
        }
        .tint(Color.cinemaAccent)
        .task { await model.favorites.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.favorites.isLoading, model.favorites.favorites.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        } else if model.favorites.favorites.isEmpty {
            ContentUnavailableView(
                "Sin favoritos",
                systemImage: "heart",
                description: Text("Toca el corazón en cualquier programa, serie, miniserie o película para guardarlo aquí.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.favorites.favorites) { favorite in
                        FavoriteRow(favorite: favorite, onTap: { open(favorite) }) {
                            Task { await model.favorites.remove(favorite) }
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    private func open(_ favorite: FavoriteItem) {
        switch favorite.kind {
        case .programa, .serie:
            if let show = favorite.asShowSummary {
                path.append(ShowRoute(show: show))
            }
        case .miniserie:
            if let show = favorite.asMiniserieShow {
                path.append(MiniserieRoute(show: show))
            }
        case .pelicula:
            if let card = favorite.asMediaCard {
                model.playback.prepare(.video(card))
            }
        }
    }
}

private struct FavoriteRow: View {
    let favorite: FavoriteItem
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.kind.category.title.uppercased())
                        .font(.caption2.bold())
                        .tracking(0.5)
                        .foregroundStyle(Color.cinemaAccent)
                    Text(favorite.title).font(.headline).lineLimit(2)
                    if let subtitle = favorite.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onRemove) {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(Color.cinemaAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quitar de favoritos")
            }
            .padding(12)
            .contentShape(.rect)
            .cinemaCard()
        }
        .buttonStyle(.plain)
    }

    private var artwork: some View {
        AsyncImage(url: favorite.posterURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.cinemaSurfaceRaised
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(.rect(cornerRadius: 12))
    }
}
