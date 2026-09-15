import AVFoundation
import Foundation

/// Thin wrapper around `AVAssetDownloadURLSession` — the official AVFoundation API for
/// persisting an HLS stream for offline playback. Kept deliberately non-actor-isolated (like
/// `HeaderResourceLoader`) since `AVAssetDownloadDelegate` callbacks arrive on an arbitrary
/// queue, not necessarily the main actor; callers are notified via `@Sendable` closures and are
/// responsible for hopping back to whatever isolation they need.
final class DownloadEngine: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    private static let sessionIdentifier = "com.superapp.mitelestreamplayer.downloads"

    private let lock = NSLock()
    // Keyed by `taskIdentifier` rather than the task itself — `URLSessionTask` isn't `Hashable`.
    private var contentIDsByTaskID: [Int: String] = [:]
    private var tasksByContentID: [String: AVAssetDownloadTask] = [:]

    var onProgress: (@Sendable (String, Double) -> Void)?
    var onFinished: (@Sendable (String, URL) -> Void)?
    var onFailed: (@Sendable (String, Error?) -> Void)?

    private lazy var session: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        return AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: OperationQueue()
        )
    }()

    override init() {
        super.init()
        // Force the background session to attach immediately rather than waiting for the first
        // download — if the app was relaunched in the background specifically because a download
        // finished, `urlSessionDidFinishEvents` needs the session/delegate already wired up to
        // receive that event and pick up the pending completion handler from the registry.
        _ = session
    }

    func startDownload(contentID: String, url: URL, headers: [String: String], title: String) {
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: title,
            assetArtworkData: nil,
            options: nil
        ) else {
            onFailed?(contentID, nil)
            return
        }
        synchronized {
            contentIDsByTaskID[task.taskIdentifier] = contentID
            tasksByContentID[contentID] = task
        }
        task.resume()
    }

    func cancelDownload(contentID: String) {
        let task = synchronized { tasksByContentID[contentID] }
        task?.cancel()
    }

    private func removeTracking(taskID: Int) -> String? {
        synchronized {
            guard let contentID = contentIDsByTaskID.removeValue(forKey: taskID) else { return nil }
            tasksByContentID.removeValue(forKey: contentID)
            return contentID
        }
    }

    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let contentID = synchronized({ contentIDsByTaskID[assetDownloadTask.taskIdentifier] }) else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected.isFinite, expected > 0 else { return }
        var loaded = 0.0
        for value in loadedTimeRanges {
            loaded += value.timeRangeValue.duration.seconds
        }
        onProgress?(contentID, min(max(loaded / expected, 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let contentID = synchronized({ contentIDsByTaskID[assetDownloadTask.taskIdentifier] }) else { return }
        onFinished?(contentID, location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard task is AVAssetDownloadTask, let contentID = removeTracking(taskID: task.taskIdentifier) else { return }
        if let error {
            onFailed?(contentID, error)
        }
    }

    /// Called after a background session (potentially one that woke the app up from scratch) has
    /// delivered all of its queued delegate callbacks — the system requires the stashed
    /// completion handler to be called at this point, or risks the app being penalized for future
    /// background launches.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let handler = BackgroundDownloadCompletionRegistry.shared.take(forIdentifier: Self.sessionIdentifier) else {
            return
        }
        DispatchQueue.main.async {
            handler()
        }
    }
}
