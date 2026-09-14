import SwiftUI

struct SeasonRoute: Hashable {
    let season: Season
}

@MainActor
struct ShowDetailView: View {
    let show: ShowSummary
    let model: AppModel

    @State private var store: SeasonsStore

    init(show: ShowSummary, model: AppModel) {
        self.show = show
        self.model = model
        _store = State(initialValue: SeasonsStore(service: model.catalog.seriesPage, refID: show.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                content
            }
            .padding(18)
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SeasonRoute.self) { route in
            CollectionsView(show: show, season: route.season, model: model)
        }
        .task { store.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let subtitle = show.subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Temporadas").font(.title3.bold()).foregroundStyle(.white)
        }
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
                    NavigationLink(value: SeasonRoute(season: season)) {
                        CatalogRow(title: season.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct CatalogRow: View {
    let title: String

    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(14)
        .cinemaCard()
    }
}
