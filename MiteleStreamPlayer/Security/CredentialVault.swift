import Foundation
import Security

protocol CredentialProviding: Sendable {
    func credentials() async throws -> PrototypeCredentials?
}

struct KeychainFailure: Error, Sendable {
    let status: OSStatus
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
        let gmid = try read(account: Account.gmid)
        let cookie = try read(account: Account.cookie)
        if let gmid, let cookie {
            return PrototypeCredentials(gmid: gmid, cookie: cookie)
        }
        let defaults = PrototypeCredentials(gmid: DefaultCredentials.gmid, cookie: DefaultCredentials.cookie)
        return defaults.isValid ? defaults : nil
    }

    func save(_ credentials: PrototypeCredentials) async throws {
        guard credentials.isValid else { throw PlaybackFailure.missingCredentials }
        try save(credentials.gmid, account: Account.gmid)
        do {
            try save(credentials.cookie, account: Account.cookie)
        } catch {
            try? delete(account: Account.gmid)
            throw error
        }
    }

    func clear() async throws {
        try delete(account: Account.gmid)
        try delete(account: Account.cookie)
    }

    private func identity(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    private func save(_ value: String, account: String) throws {
        let base = identity(account: account)
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

    private func read(account: String) throws -> String? {
        var query = identity(account: account)
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

    private func delete(account: String) throws {
        let status = SecItemDelete(identity(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure(status: status)
        }
    }
}
