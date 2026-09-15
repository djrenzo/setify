import Foundation
import Security

protocol CredentialProviding: Sendable {
    func credentials() async throws -> PrototypeCredentials?
}

struct KeychainFailure: Error, Sendable {
    let status: OSStatus
}

/// Stateless Keychain CRUD shared by `CredentialVault` (Mediaset) and `AtresCredentialVault`
/// (Atresplayer) — both are simple service+account generic-password items, just with different
/// account names and value shapes.
enum KeychainStore {
    static func save(_ value: String, service: String, account: String) throws {
        let base = identity(service: service, account: account)
        var add = base
        add[kSecValueData] = Data(value.utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update: [CFString: Any] = [kSecValueData: Data(value.utf8)]
            let updateStatus = SecItemUpdate(base as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainFailure(status: updateStatus)
            }
        default:
            throw KeychainFailure(status: status)
        }
    }

    static func read(service: String, account: String) throws -> String? {
        var query = identity(service: service, account: account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainFailure(status: errSecDecode)
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainFailure(status: status)
        }
    }

    static func delete(service: String, account: String) throws {
        let status = SecItemDelete(identity(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure(status: status)
        }
    }

    private static func identity(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

actor CredentialVault: CredentialProviding {
    private enum Account {
        static let gmid = "prototype.gmid"
        static let cookie = "prototype.cookie"
    }

    private let service: String

    init(service: String = "com.superapp.mitelestreamplayer.prototype") {
        self.service = service
    }

    func credentials() async throws -> PrototypeCredentials? {
        let gmid = try KeychainStore.read(service: service, account: Account.gmid)
        let cookie = try KeychainStore.read(service: service, account: Account.cookie)
        if let gmid, let cookie {
            return PrototypeCredentials(gmid: gmid, cookie: cookie)
        }
        let defaults = PrototypeCredentials(gmid: DefaultCredentials.gmid, cookie: DefaultCredentials.cookie)
        return defaults.isValid ? defaults : nil
    }

    func save(_ credentials: PrototypeCredentials) async throws {
        guard credentials.isValid else { throw PlaybackFailure.missingCredentials }
        try KeychainStore.save(credentials.gmid, service: service, account: Account.gmid)
        do {
            try KeychainStore.save(credentials.cookie, service: service, account: Account.cookie)
        } catch {
            try? KeychainStore.delete(service: service, account: Account.gmid)
            throw error
        }
    }

    func clear() async throws {
        try KeychainStore.delete(service: service, account: Account.gmid)
        try KeychainStore.delete(service: service, account: Account.cookie)
    }
}

/// Atresplayer needs only a single value: the `A3PSID` login cookie, attached as a `Cookie`
/// header when a player endpoint demands a registered/paid session. See
/// API_STREAM_RESOLUTION_ATRES.md §3 — unlike Mediaset there's no signing/token exchange, this
/// is a plain cookie value copied from a logged-in browser session.
protocol AtresSessionProviding: Sendable {
    func session() async throws -> String?
}

actor AtresCredentialVault: AtresSessionProviding {
    private enum Account {
        static let a3psid = "prototype.atresSession"
    }

    private let service: String

    init(service: String = "com.superapp.mitelestreamplayer.prototype") {
        self.service = service
    }

    func session() async throws -> String? {
        if let stored = try KeychainStore.read(service: service, account: Account.a3psid), !stored.isEmpty {
            return stored
        }
        return AtresDefaultCredentials.session.isEmpty ? nil : AtresDefaultCredentials.session
    }

    func save(_ value: String) async throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlaybackFailure.missingCredentials }
        try KeychainStore.save(trimmed, service: service, account: Account.a3psid)
    }

    func clear() async throws {
        try KeychainStore.delete(service: service, account: Account.a3psid)
    }
}
