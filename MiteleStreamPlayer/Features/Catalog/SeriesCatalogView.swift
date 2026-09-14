import SwiftUI

@MainActor
struct SeriesCatalogView: View {
    @State var store: SeriesCatalogStore
    let model: AppModel

    var body: some View {
        ShowGridView(
            shows: store.shows,
            isLoading: store.isLoading,
            errorMessage: store.errorMessage,
            favoriteKind: .serie,
            favorites: model.favorites,
            onReachEnd: store.loadNextPage
        )
        .navigationTitle("Series")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ShowRoute.self) { route in
            ShowDetailView(show: route.show, model: model)
        }
        .task { store.loadInitial() }
    }
}
