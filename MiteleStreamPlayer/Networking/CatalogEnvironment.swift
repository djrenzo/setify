import Foundation

struct CatalogEnvironment: Sendable {
    let showCatalog: any ShowCatalogFetching
    let episodeCatalog: any EpisodeCatalogFetching
    let seriesPage: any SeriesPageFetching
    let editorialIndex: any EditorialIndexFetching
    let miniserieTabs: any MiniserieTabsFetching

    static func live(client: HTTPClient) -> CatalogEnvironment {
        let graphQL = GraphQLCatalogService(client: client)
        return CatalogEnvironment(
            showCatalog: graphQL,
            episodeCatalog: graphQL,
            seriesPage: SeriesPageService(client: client),
            editorialIndex: BitbanEditorialIndexService(client: client),
            miniserieTabs: MiniserieTabsService(client: client)
        )
    }
}
