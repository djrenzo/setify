import SwiftUI

@MainActor
struct SeriesCatalogView: View {
    @State var store: SeriesCatalogStore
    @State var atresStore: AtresShowCatalogStore
    let model: AppModel

    @State private var source = PlatformSource.mitele

    var body: some View {
        VStack(spacing: 0) {
            PlatformSourcePicker(selection: $source)
            switch source {
            case .mitele:
                ShowGridView(
                    shows: store.shows,
                    isLoading: store.isLoading,
                    errorMessage: store.errorMessage,
                    favoriteKind: .serie,
                    favorites: model.favorites,
                    onReachEnd: store.loadNextPage
                )
                .task { store.loadInitial() }
            case .atresplayer:
                ShowGridView(
                    shows: atresStore.shows,
                    isLoading: atresStore.isLoading,
                    errorMessage: atresStore.errorMessage,
                    favoriteKind: .atresSerie,
                    favorites: model.favorites,
                    onReachEnd: atresStore.loadNextPage
                )
                .task { atresStore.loadInitial() }
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle("Series")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ShowRoute.self) { route in
            showDetailDestination(for: route.show, favoriteKind: route.favoriteKind, model: model)
        }
    }
}
