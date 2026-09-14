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

    init(
        channels: ChannelStore,
        search: SearchStore,
        playback: PlaybackCoordinator,
        credentialStatus: CredentialStatusStore,
        vault: CredentialVault
    ) {
        self.channels = channels
        self.search = search
        self.playback = playback
        self.credentialStatus = credentialStatus
        self.vault = vault
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
            vault: vault
        )
    }
}
