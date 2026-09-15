import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let channels: ChannelStore
    let search: SearchStore
    let playback: PlaybackCoordinator
    let credentialStatus: CredentialStatusStore
    let vault: CredentialVault
    let atresVault: AtresCredentialVault
    let catalog: CatalogEnvironment
    let favorites: FavoritesStore
    let watchProgress: WatchProgressStore
    let downloads: DownloadStore

    init(
        channels: ChannelStore,
        search: SearchStore,
        playback: PlaybackCoordinator,
        credentialStatus: CredentialStatusStore,
        vault: CredentialVault,
        atresVault: AtresCredentialVault,
        catalog: CatalogEnvironment,
        favorites: FavoritesStore,
        watchProgress: WatchProgressStore,
        downloads: DownloadStore
    ) {
        self.channels = channels
        self.search = search
        self.playback = playback
        self.credentialStatus = credentialStatus
        self.vault = vault
        self.atresVault = atresVault
        self.catalog = catalog
        self.favorites = favorites
        self.watchProgress = watchProgress
        self.downloads = downloads
    }

    static func live() -> AppModel {
        let vault = CredentialVault()
        let atresVault = AtresCredentialVault()
        let client = HTTPClient()
        let identity = GigyaIdentityService(client: client, credentialProvider: vault)
        let resolver = MediasetStreamResolver(
            client: client,
            credentials: vault,
            identityService: identity,
            atresPlayer: AtresPlayerService(client: client, sessionProvider: atresVault)
        )
        let channelStore = ChannelStore(repository: JSONChannelRepository())
        let searchService = CombinedSearchService(
            mitele: MiteleSearchService(client: client),
            atres: AtresSearchService(client: client)
        )
        let searchStore = SearchStore(service: searchService)
        let playback = PlaybackCoordinator(resolver: resolver, identityService: identity)
        return AppModel(
            channels: channelStore,
            search: searchStore,
            playback: playback,
            credentialStatus: CredentialStatusStore(vault: vault),
            vault: vault,
            atresVault: atresVault,
            catalog: CatalogEnvironment.live(client: client),
            favorites: FavoritesStore(repository: JSONFavoritesRepository()),
            watchProgress: WatchProgressStore(repository: JSONWatchProgressRepository()),
            downloads: DownloadStore(repository: JSONDownloadsRepository(), resolver: resolver)
        )
    }
}
