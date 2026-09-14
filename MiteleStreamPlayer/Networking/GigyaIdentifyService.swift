import Foundation

struct SigningIdentity: Sendable {
    let uid: String
    let signature: String
    let timestamp: Int64
}

actor GigyaIdentityService {
    private struct CachedIdentity {
        let credentials: PrototypeCredentials
        let identity: SigningIdentity
    }

    private let client: HTTPClient
    private let credentialProvider: any CredentialProviding
    private var cached: CachedIdentity?

    init(client: HTTPClient, credentialProvider: any CredentialProviding) {
        self.client = client
        self.credentialProvider = credentialProvider
    }

    func identity() async throws -> SigningIdentity {
        guard let credentials = try await credentialProvider.credentials(), credentials.isValid else {
            throw PlaybackFailure.missingCredentials
        }
        if let cached, cached.credentials == credentials, isFresh(cached.identity) {
            return cached.identity
        }

        let values = try signingParameters(from: credentials.cookie)
        guard var components = URLComponents(url: APIURL.gigyaAccount, resolvingAgainstBaseURL: false) else {
            throw PlaybackFailure.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "APIKey", value: values.apiKey),
            URLQueryItem(name: "sdk", value: "js_latest"),
            URLQueryItem(name: "login_token", value: values.loginToken),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw PlaybackFailure.invalidURL }

        let endpoint = Endpoint(
            url: url,
            headers: APIConfiguration.sessionHeaders(gmid: credentials.gmid)
        )
        do {
            let response = try await client.decode(AccountInfoResponse.self, from: endpoint)
            guard response.errorCode == nil || response.errorCode == 0 else {
                throw PlaybackFailure.sessionExpired
            }
            guard let uid = response.uid?.nonEmpty,
                  let signature = response.uidSignature?.nonEmpty,
                  let timestamp = response.signatureTimestamp else {
                throw PlaybackFailure.sessionExpired
            }
            let identity = SigningIdentity(uid: uid, signature: signature, timestamp: timestamp)
            cached = CachedIdentity(credentials: credentials, identity: identity)
            return identity
        } catch let failure as PlaybackFailure {
            throw failure
        } catch let error as HTTPClientError {
            throw error.playbackFailure
        }
    }

    func invalidate() {
        cached = nil
    }

    private func isFresh(_ identity: SigningIdentity) -> Bool {
        Date.now.timeIntervalSince1970 < Double(identity.timestamp) + 7_200
    }

    private func signingParameters(from cookie: String) throws -> (apiKey: String, loginToken: String) {
        let query = cookie.split(separator: "?", maxSplits: 1).last.map(String.init) ?? cookie
        var components = URLComponents()
        components.percentEncodedQuery = query
        let items = components.queryItems ?? []
        let apiKey = items.first(where: { $0.name == "APIKey" })?.value?.nonEmpty
        let token = items.first(where: { $0.name == "login_token" })?.value?.nonEmpty
        guard let apiKey, let token else { throw PlaybackFailure.sessionExpired }
        return (apiKey, token)
    }
}

private struct AccountInfoResponse: Decodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case uid = "UID"
        case uidSignature = "UIDSignature"
        case signatureTimestamp
        case errorCode
    }

    let uid: String?
    let uidSignature: String?
    let signatureTimestamp: Int64?
    let errorCode: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try? container.decode(String.self, forKey: .uid)
        uidSignature = try? container.decode(String.self, forKey: .uidSignature)
        errorCode = try? container.decode(Int.self, forKey: .errorCode)
        if let value = try? container.decode(Int64.self, forKey: .signatureTimestamp) {
            signatureTimestamp = value
        } else if let value = try? container.decode(Double.self, forKey: .signatureTimestamp) {
            signatureTimestamp = Int64(value)
        } else if let value = try? container.decode(String.self, forKey: .signatureTimestamp) {
            signatureTimestamp = Int64(value)
        } else {
            signatureTimestamp = nil
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
