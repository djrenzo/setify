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
                atresStore: AtresShowCatalogStore(
                    service: model.catalog.atresRow,
                    baseURL: AtresCatalogURLBuilder.formatSearch(categoryID: AtresCatalogID.categoryProgramas)
                ),
                model: model
            )
        case .series:
            SeriesCatalogView(
                store: SeriesCatalogStore(service: model.catalog.editorialIndex),
                atresStore: AtresShowCatalogStore(
                    service: model.catalog.atresRow,
                    baseURL: AtresCatalogURLBuilder.formatSearch(categoryID: AtresCatalogID.categorySeries)
                ),
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
                atresStore: AtresRecordingCatalogStore(
                    service: model.catalog.atresRow,
                    baseURL: AtresCatalogURLBuilder.recordingSearch(categoryID: AtresCatalogID.categoryCine)
                ),
                model: model
            )
        }
    }
}
