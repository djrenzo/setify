import SwiftUI

struct ShowRoute: Hashable {
    let show: ShowSummary
}

/// `ShowRoute` is shared by both Mitele and Atresplayer show grids — an Atres-sourced
/// `ShowSummary.id` is namespaced with an `"atres:"` prefix (see `AtresModels.swift`), which is
/// enough to route to the right detail pipeline without a second route type.
@ViewBuilder
@MainActor
func showDetailDestination(for show: ShowSummary, model: AppModel) -> some View {
    if show.id.isAtresID {
        AtresShowDetailView(show: show, model: model)
    } else {
        ShowDetailView(show: show, model: model)
    }
}

struct ShowGridView: View {
    let shows: [ShowSummary]
    let isLoading: Bool
    let errorMessage: String?
    let favoriteKind: FavoriteKind
    let favorites: FavoritesStore
    let onReachEnd: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(shows) { show in
                    NavigationLink(value: ShowRoute(show: show)) {
                        ShowTile(show: show, isFavorite: favorites.isFavorite(favoriteID(for: show))) {
                            Task { await favorites.toggle(FavoriteItem(show: show, kind: favoriteKind)) }
                        }
                    }
                    .buttonStyle(.plain)
                    .task {
                        if show.id == shows.last?.id {
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
            if let errorMessage, shows.isEmpty {
                ContentUnavailableView(
                    "No se pudo cargar",
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
                .padding(.top, 60)
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
    }

    private func favoriteID(for show: ShowSummary) -> String {
        FavoriteItem(show: show, kind: favoriteKind).id
    }
}

private struct ShowTile: View {
    let show: ShowSummary
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SquarePosterImage(url: show.posterURL)
                .overlay(alignment: .topTrailing) {
                    FavoriteHeartButton(isFavorite: isFavorite, onToggle: onToggleFavorite)
                }
            Text(show.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
            if let subtitle = show.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
