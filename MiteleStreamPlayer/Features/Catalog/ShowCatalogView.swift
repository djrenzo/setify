import SwiftUI

@MainActor
struct ShowCatalogView: View {
    let title: String
    @State var store: ShowCatalogStore
    let model: AppModel

    var body: some View {
        ShowGridView(
            shows: store.shows,
            isLoading: store.isLoading,
            errorMessage: store.errorMessage,
            onReachEnd: store.loadNextPage
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ShowRoute.self) { route in
            ShowDetailView(show: route.show, model: model)
        }
        .task { store.loadInitial() }
    }
}
