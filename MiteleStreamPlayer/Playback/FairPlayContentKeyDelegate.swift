import AVFoundation
import Foundation
import os

/// Step-by-step trace of the FairPlay exchange, visible in the Xcode console and Console.app
/// (subsystem `com.superapp.mitele`, category `fairplay`) and mirrored into the in-app
/// `DiagnosticsLog` so it can be read and copied from the player's failure overlay. The license
/// server's status + body is the decisive diagnostic when a DRM-only episode won't start.
private let fairPlayLog = Logger(subsystem: "com.superapp.mitele", category: "fairplay")

private func fpTrace(_ message: String) {
    fairPlayLog.info("\(message, privacy: .public)")
    DiagnosticsLog.record(message)
}

private func fpError(_ message: String) {
    fairPlayLog.error("\(message, privacy: .public)")
    DiagnosticsLog.record("⚠️ \(message)")
}

/// Handles FairPlay Streaming key requests for a single DRM-protected `AVURLAsset`.
///
/// The clear-HLS shortcut (`main.ism`) used everywhere else in the app doesn't exist for some
/// uploads — the CDN answers the clear manifest with `403` and only serves the encrypted
/// `hls-fairplay.ism` variant, whose playlist carries `#EXT-X-SESSION-KEY … skd://…`. AVPlayer
/// then asks for a content key, and this delegate runs the standard exchange:
///
///   1. fetch the provider's FairPlay application certificate,
///   2. build a Server Playback Context (SPC) using `drm.releasePid` as the content identifier
///      (NOT the `skd://` key id from the manifest — theplatform's own release pid, resolved
///      ahead of time by `MediasetStreamResolver` via its `playback/check` + SMIL selector),
///   3. POST the SPC to the key server,
///   4. hand the returned Content Key Context (CKC) back to AVFoundation.
///
/// The decrypted key never leaves Apple's secure path — this class only shuttles the opaque
/// SPC/CKC blobs. One instance is created per playback and retained by `PlayerTransport` for as
/// long as the item lives (the content key session holds its delegate weakly).
final class FairPlayContentKeyDelegate: NSObject, AVContentKeySessionDelegate, @unchecked Sendable {
    private let drm: FairPlayDRM
    private let session: URLSession
    /// The application certificate is identical for every key request, so fetch it once.
    private let certificateLock = NSLock()
    private var cachedCertificate: Data?

    init(drm: FairPlayDRM) {
        self.drm = drm
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        super.init()
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        handle(keyRequest)
    }

    /// A renewing request (the CDN rotated the key mid-stream) is served the same way.
    func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        handle(keyRequest)
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequest keyRequest: AVContentKeyRequest,
        didFailWithError err: any Error
    ) {
        // Nothing to retry against — the request already carries the failure to the player item.
    }

    private func handle(_ keyRequest: AVContentKeyRequest) {
        fpTrace("key request received, identifier=\(String(describing: keyRequest.identifier)), releasePid=\(drm.releasePid)")
        guard let assetID = drm.releasePid.data(using: .utf8), !drm.releasePid.isEmpty else {
            fpError("empty releasePid — cannot build content id")
            keyRequest.processContentKeyResponseError(FairPlayError.invalidKeyIdentifier)
            return
        }

        let appCertificate: Data
        do {
            appCertificate = try certificate()
            fpTrace("certificate loaded, \(appCertificate.count) bytes")
        } catch {
            fpError("certificate fetch failed: \(String(describing: error))")
            keyRequest.processContentKeyResponseError(error)
            return
        }

        // `AVContentKeyRequest` isn't `Sendable`, but it's only ever touched on this delegate's
        // serial queue and inside the continuation below, so opting it out of the check is safe.
        nonisolated(unsafe) let request = keyRequest

        request.makeStreamingContentKeyRequestData(
            forApp: appCertificate,
            contentIdentifier: assetID,
            options: [AVContentKeyRequestProtocolVersionsKey: [1]]
        ) { [weak self] spcData, error in
            guard let self else { return }
            if let error {
                fpError("SPC generation failed: \(String(describing: error))")
                request.processContentKeyResponseError(error)
                return
            }
            guard let spcData else {
                fpError("SPC generation returned no data")
                request.processContentKeyResponseError(FairPlayError.missingSPC)
                return
            }
            fpTrace("SPC generated, \(spcData.count) bytes")
            Task { await self.requestKey(spc: spcData, keyRequest: request) }
        }
    }

    private func requestKey(spc: Data, keyRequest: AVContentKeyRequest) async {
        do {
            let ckc = try await fetchCKC(spc: spc)
            fpTrace("CKC decoded, \(ckc.count) bytes — handing key to player ✅")
            let response = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc)
            keyRequest.processContentKeyResponse(response)
        } catch {
            fpError("license/CKC step failed: \(String(describing: error))")
            keyRequest.processContentKeyResponseError(error)
        }
    }

    /// theplatform's key server (`fpls/web/FairPlay?form=json`) takes the SPC in a JSON envelope
    /// `{"getFairplayLicense":{"spcMessage":…,"releasePid":…}}` — `releasePid` also duplicated in
    /// the URL query, matching a captured real request — authenticates via `Authorization: Basic
    /// base64(":"+beToken)` (the same scheme as the SMIL fetch, NOT a `token=` query param as
    /// theplatform's generic docs would suggest), and answers
    /// `{"getFairplayLicenseResponse":{"ckcResponse":<base64>}}`.
    private func fetchCKC(spc: Data) async throws -> Data {
        guard var components = URLComponents(url: drm.licenseURL, resolvingAgainstBaseURL: false) else {
            throw FairPlayError.licenseServer(-1)
        }
        var query = components.queryItems ?? []
        query.append(URLQueryItem(name: "releasePid", value: drm.releasePid))
        components.queryItems = query
        let url = components.url ?? drm.licenseURL

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (field, value) in drm.licenseHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let basic = Data(":\(drm.token)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "getFairplayLicense": [
                "spcMessage": spc.base64EncodedString(),
                "releasePid": drm.releasePid
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let tokenDesc = drm.token.isEmpty ? "empty" : "\(drm.token.count) chars"
        fpTrace("POST license (releasePid=\(drm.releasePid), token \(tokenDesc))")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let bodyText = String(data: data.prefix(600), encoding: .utf8) ?? "<\(data.count) bytes non-utf8>"
        fpTrace("license status=\(status) body=\(bodyText)")
        guard (200..<300).contains(status) else {
            throw FairPlayError.licenseServer(status)
        }
        return try Self.decodeCKC(from: data)
    }

    private func certificate() throws -> Data {
        certificateLock.lock()
        defer { certificateLock.unlock() }
        if let cachedCertificate { return cachedCertificate }
        let data = try Data(contentsOf: drm.certificateURL)
        cachedCertificate = data
        return data
    }

    /// theplatform answers `{"getFairplayLicenseResponse":{"ckcResponse":"<base64>"}}` (confirmed
    /// against a real license exchange); a few other flat shapes and a bare base64 / raw body are
    /// also accepted for robustness.
    private static func decodeCKC(from data: Data) throws -> Data {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let response = object["getFairplayLicenseResponse"] as? [String: Any] {
                for key in ["ckcResponse", "ckcMessage", "ckc"] {
                    if let value = response[key] as? String, let decoded = Data(base64Encoded: value) {
                        return decoded
                    }
                }
            }
            for key in ["ckcResponse", "ckcMessage", "ckc", "CkcMessage", "license"] {
                if let value = object[key] as? String, let decoded = Data(base64Encoded: value) {
                    return decoded
                }
            }
            throw FairPlayError.malformedCKC
        }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let decoded = Data(base64Encoded: text) {
            return decoded
        }
        guard !data.isEmpty else { throw FairPlayError.malformedCKC }
        return data
    }
}

enum FairPlayError: Error {
    case invalidKeyIdentifier
    case missingSPC
    case malformedCKC
    case licenseServer(Int)
}
