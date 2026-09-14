import SwiftUI

struct CollectionRoute: Hashable {
    let collection: EpisodeCollection
}

@MainActor
struct CollectionsView: View {
    let show: ShowSummary
    let season: Season
    let model: AppModel

    @State private var store: CollectionsStore

    init(show: ShowSummary, season: Season, model: AppModel) {
        self.show = show
        self.season = season
        self.model = model
        _store = State(initialValue: CollectionsStore(service: model.catalog.seriesPage, seasonID: season.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Colecciones").font(.title3.bold()).foregroundStyle(.white)
                content
            }
            .padding(18)
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle(season.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CollectionRoute.self) { route in
            EpisodesListView(title: route.collection.title, collectionID: route.collection.id, model: model)
        }
        .task { store.load() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading, store.collections.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        } else if let message = store.errorMessage, store.collections.isEmpty {
            ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(message))
        } else if store.collections.isEmpty {
            ContentUnavailableView("Sin colecciones", systemImage: "square.stack.3d.up.slash")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(store.collections) { collection in
                    NavigationLink(value: CollectionRoute(collection: collection)) {
                        CatalogRow(title: collection.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
