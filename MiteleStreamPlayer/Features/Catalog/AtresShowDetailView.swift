import SwiftUI

struct AtresSeasonRoute: Hashable {
    let season: Season
}

/// Atresplayer's FORMAT pipeline has no "collections" layer between seasons and episodes —
/// unlike Mitele, tapping a season here goes straight to its episode list.
@MainActor
struct AtresShowDetailView: View {
    let show: ShowSummary
    let model: AppModel

    @State private var store: AtresSeasonsStore

    init(show: ShowSummary, model: AppModel) {
        self.show = show
        self.model = model
        _store = State(initialValue: AtresSeasonsStore(
            service: model.catalog.atresFormatPage,
            formatID: show.id.strippingAtresPrefix
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Temporadas").font(.title3.bold()).foregroundStyle(.white)
                content
            }
            .padding(18)
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AtresSeasonRoute.self) { route in
            AtresEpisodesListView(show: show, season: route.season, model: model)
        }
        .task { store.load() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading, store.seasons.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        } else if let message = store.errorMessage, store.seasons.isEmpty {
            ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(message))
        } else if store.seasons.isEmpty {
            ContentUnavailableView("Sin temporadas", systemImage: "rectangle.stack.badge.minus")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(store.seasons) { season in
                    NavigationLink(value: AtresSeasonRoute(season: season)) {
                        CatalogRow(title: season.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
