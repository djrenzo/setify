import AVFoundation
import Foundation
import UniformTypeIdentifiers

final class HeaderResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private struct LoadingContext {
        let request: AVAssetResourceLoadingRequest
        var response: HTTPURLResponse?
        var data = Data()
    }

    let resourceQueue = DispatchQueue(label: "com.superapp.mitele.resource-loader")

    private let headers: [String: String]
    private let lock = NSLock()
    private let sessionQueue: OperationQueue
    private var contexts: [Int: LoadingContext] = [:]
    private var tasksByRequest: [ObjectIdentifier: URLSessionDataTask] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: sessionQueue)
    }()

    init(headers: [String: String]) {
        self.headers = headers
        let queue = OperationQueue()
        queue.name = "com.superapp.mitele.resource-session"
        queue.maxConcurrentOperationCount = 1
        sessionQueue = queue
        super.init()
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let requestedURL = loadingRequest.request.url,
              let sourceURL = Self.sourceURL(from: requestedURL) else {
            return false
        }

        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        applyHeaders(to: &request)
        if !Self.looksLikePlaylistURL(sourceURL) {
            applyRange(from: loadingRequest.dataRequest, to: &request)
        }

        let task = session.dataTask(with: request)
        synchronized {
            contexts[task.taskIdentifier] = LoadingContext(request: loadingRequest)
            tasksByRequest[ObjectIdentifier(loadingRequest)] = task
        }
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let task = synchronized {
            tasksByRequest.removeValue(forKey: ObjectIdentifier(loadingRequest))
        }
        if let task {
            synchronized { contexts.removeValue(forKey: task.taskIdentifier) }
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            finishWithAuthorizationError(taskID: dataTask.taskIdentifier)
            completionHandler(.cancel)
            return
        }
        synchronized {
            contexts[dataTask.taskIdentifier]?.response = http
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        var exceededLimit = false
        synchronized {
            guard var context = contexts[dataTask.taskIdentifier] else { return }
            context.data.append(data)
            exceededLimit = context.data.count > 40 * 1_024 * 1_024
            contexts[dataTask.taskIdentifier] = context
        }
        if exceededLimit {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let context = removeContext(taskID: task.taskIdentifier) else { return }
        if let error {
            context.request.finishLoading(with: error)
            return
        }
        guard let response = context.response else {
            context.request.finishLoading(with: URLError(.badServerResponse))
            return
        }
        finish(context: context, response: response, sourceURL: task.originalRequest?.url)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        var redirected = request
        applyHeaders(to: &redirected)
        completionHandler(redirected)
    }

    private func finish(
        context: LoadingContext,
        response: HTTPURLResponse,
        sourceURL: URL?
    ) {
        let isPlaylist = Self.isPlaylist(response: response, url: sourceURL, data: context.data)
        let data = isPlaylist ? Self.rewritingPlaylist(context.data) : context.data
        configureContentInformation(
            context.request.contentInformationRequest,
            response: response,
            contentLength: data.count,
            isPlaylist: isPlaylist
        )
        let responseData = Self.requestedData(
            from: data,
            dataRequest: context.request.dataRequest,
            response: response
        )
        context.request.dataRequest?.respond(with: responseData)
        context.request.finishLoading()
    }

    private func configureContentInformation(
        _ information: AVAssetResourceLoadingContentInformationRequest?,
        response: HTTPURLResponse,
        contentLength: Int,
        isPlaylist: Bool
    ) {
        guard let information else { return }
        let mimeType = response.mimeType ?? "application/octet-stream"
        information.contentType = if isPlaylist {
            UTType(filenameExtension: "m3u8")?.identifier ?? "public.data"
        } else {
            UTType(mimeType: mimeType)?.identifier ?? "public.data"
        }
        information.contentLength = if isPlaylist {
            Int64(contentLength)
        } else {
            Self.totalLength(response: response) ?? Int64(contentLength)
        }
        information.isByteRangeAccessSupported = true
    }

    private func finishWithAuthorizationError(taskID: Int) {
        guard let context = removeContext(taskID: taskID) else { return }
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorUserAuthenticationRequired
        )
        context.request.finishLoading(with: error)
    }

    private func removeContext(taskID: Int) -> LoadingContext? {
        synchronized {
            guard let context = contexts.removeValue(forKey: taskID) else { return nil }
            tasksByRequest.removeValue(forKey: ObjectIdentifier(context.request))
            return context
        }
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private func applyRange(
        from dataRequest: AVAssetResourceLoadingDataRequest?,
        to request: inout URLRequest
    ) {
        guard let dataRequest else { return }
        let start = dataRequest.currentOffset
        if dataRequest.requestsAllDataToEndOfResource {
            request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
        } else {
            let end = start + Int64(dataRequest.requestedLength) - 1
            request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        }
    }

    private func synchronized<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    static func customURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "msphttps"
        case "http": components.scheme = "msphttp"
        default: return nil
        }
        return components.url
    }

    private static func sourceURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "msphttps": components.scheme = "https"
        case "msphttp": components.scheme = "http"
        default: return nil
        }
        return components.url
    }

    private static func looksLikePlaylistURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".m3u8") || path.contains(".ism")
    }

    private static func isPlaylist(
        response: HTTPURLResponse,
        url: URL?,
        data: Data
    ) -> Bool {
        if response.mimeType?.lowercased().contains("mpegurl") == true { return true }
        if url?.pathExtension.lowercased() == "m3u8" { return true }
        guard let prefix = String(data: data.prefix(24), encoding: .utf8) else { return false }
        return prefix.contains("#EXTM3U")
    }

    private static func rewritingPlaylist(_ data: Data) -> Data {
        guard var playlist = String(data: data, encoding: .utf8) else { return data }
        playlist = playlist.replacingOccurrences(of: "https://", with: "msphttps://")
        playlist = playlist.replacingOccurrences(of: "http://", with: "msphttp://")
        return Data(playlist.utf8)
    }

    private static func requestedData(
        from data: Data,
        dataRequest: AVAssetResourceLoadingDataRequest?,
        response: HTTPURLResponse
    ) -> Data {
        guard let dataRequest else { return data }
        var result = data
        if response.statusCode == 200, dataRequest.requestedOffset > 0 {
            let offset = min(Int(dataRequest.requestedOffset), result.count)
            result = Data(result.dropFirst(offset))
        }
        if !dataRequest.requestsAllDataToEndOfResource {
            result = Data(result.prefix(dataRequest.requestedLength))
        }
        return result
    }

    private static func totalLength(response: HTTPURLResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let total = contentRange.split(separator: "/").last,
           let length = Int64(total) {
            return length
        }
        let expected = response.expectedContentLength
        return expected > 0 ? expected : nil
    }
}