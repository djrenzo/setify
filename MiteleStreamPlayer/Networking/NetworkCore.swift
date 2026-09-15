import Foundation

struct Endpoint: Sendable {
    var url: URL
    var method = "GET"
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = 30

    func request() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}

enum HTTPClientError: Error, Sendable {
    case invalidResponse
    case status(Int)
    case responseTooLarge
    case transport(Int)
    case decoding
}

actor HTTPClient {
    private let session: URLSession
    private let maximumResponseSize = 12 * 1_024 * 1_024

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func data(for endpoint: Endpoint) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: endpoint.request())
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw HTTPClientError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw HTTPClientError.status(http.statusCode)
            }
            guard data.count <= maximumResponseSize else {
                throw HTTPClientError.responseTooLarge
            }
            return data
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw HTTPClientError.transport(error.code.rawValue)
        }
    }

    func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from endpoint: Endpoint
    ) async throws -> T {
        let data = try await data(for: endpoint)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HTTPClientError.decoding
        }
    }

    /// Unlike `data(for:)`, doesn't throw on a non-2xx status — the response body is returned
    /// either way. Needed when the error body itself carries information worth inspecting (e.g.
    /// Atresplayer's `player/v1/episode` distinguishing `required_registered` from
    /// `required_paid` in its `403` body — see `AtresPlayerService`).
    func rawData(for endpoint: Endpoint) async throws -> (status: Int, data: Data) {
        do {
            let (data, response) = try await session.data(for: endpoint.request())
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw HTTPClientError.invalidResponse
            }
            guard data.count <= maximumResponseSize else {
                throw HTTPClientError.responseTooLarge
            }
            return (http.statusCode, data)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw HTTPClientError.transport(error.code.rawValue)
        }
    }
}

extension HTTPClientError {
    var playbackFailure: PlaybackFailure {
        switch self {
        case .status(401), .status(403): .sessionExpired
        case .decoding, .invalidResponse, .responseTooLarge: .apiChanged
        case .status, .transport: .network
        }
    }
}
