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
        self.catalog = catalog
        self.favorites = favorites
        self.watchProgress = watchProgress
        self.downloads = downloads
    }

    static func live() -> AppModel {
        let vault = CredentialVault()
        let client = HTTPClient()
        let identity = GigyaIdentityService(client: client, credentialProvider: vault)
        let resolver = MediasetStreamResolver(
            client: client,
            credentials: vault,
            identityService: identity
        )
        let channelStore = ChannelStore(repository: JSONChannelRepository())
        let searchStore = SearchStore(service: MiteleSearchService(client: client))
        let playback = PlaybackCoordinator(resolver: resolver, identityService: identity)
        return AppModel(
            channels: channelStore,
            search: searchStore,
            playback: playback,
            credentialStatus: CredentialStatusStore(vault: vault),
            vault: vault,
            catalog: CatalogEnvironment.live(client: client),
            favorites: FavoritesStore(repository: JSONFavoritesRepository()),
            watchProgress: WatchProgressStore(repository: JSONWatchProgressRepository()),
            downloads: DownloadStore(repository: JSONDownloadsRepository(), resolver: resolver)
        )
    }
}
