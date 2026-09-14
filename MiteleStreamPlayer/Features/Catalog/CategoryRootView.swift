import SwiftUI

enum CatalogRefID {
    // Top-level GraphQL listing ref_id for "Programas". See API_STREAM_RESOLUTION.md §11, §12.
    static let programas = "22Z26bWQ2cEi3sNWOb2Ke8"
}

@MainActor
struct CategoryRootView: View {
    let category: CatalogCategory
    let model: AppModel

    var body: some View {
        switch category {
        case .programas:
            ShowCatalogView(
                title: category.title,
                favoriteKind: .programa,
                store: ShowCatalogStore(service: model.catalog.showCatalog, refID: CatalogRefID.programas),
                model: model
            )
        case .series:
            SeriesCatalogView(
                store: SeriesCatalogStore(service: model.catalog.editorialIndex),
                model: model
            )
        case .miniseries:
            MiniseriesCatalogView(
                store: MiniseriesCatalogStore(service: model.catalog.editorialIndex),
                model: model
            )
        case .peliculas:
            PeliculasCatalogView(
                store: PeliculasCatalogStore(service: model.catalog.editorialIndex),
                model: model
            )
        }
    }
}
