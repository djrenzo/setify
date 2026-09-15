import SwiftUI

/// Atresplayer-only category — "Informativos" in the reference addon — with no Mitele
/// counterpart to merge with, unlike Programas/Series/Películas, so there's no
/// `PlatformSourcePicker` here.
@MainActor
struct NoticiasCatalogView: View {
    @State var store: AtresShowCatalogStore
    let model: AppModel

    var body: some View {
        ShowGridView(
            shows: store.shows,
            isLoading: store.isLoading,
            errorMessage: store.errorMessage,
            favoriteKind: .atresNoticia,
            favorites: model.favorites,
            onReachEnd: store.loadNextPage
        )
        .task { store.loadInitial() }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle("Noticias")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ShowRoute.self) { route in
            showDetailDestination(for: route.show, favoriteKind: route.favoriteKind, model: model)
        }
    }
}
