import Foundation
import Observation

@MainActor
@Observable
final class CredentialStatusStore {
    private let vault: CredentialVault

    var hasCredentials = false
    var isLoading = true

    init(vault: CredentialVault) {
        self.vault = vault
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            hasCredentials = try await vault.credentials()?.isValid == true
        } catch {
            hasCredentials = false
        }
    }
}
