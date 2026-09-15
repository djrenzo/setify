import Foundation

/// Bridges `UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`
/// — which can fire before the SwiftUI app's own state (and therefore `DownloadEngine`) exists —
/// to whichever `DownloadEngine` instance later re-attaches to that same background session.
final class BackgroundDownloadCompletionRegistry: @unchecked Sendable {
    static let shared = BackgroundDownloadCompletionRegistry()

    private let lock = NSLock()
    private var handlers: [String: () -> Void] = [:]

    private init() {}

    func store(_ handler: @escaping () -> Void, forIdentifier identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[identifier] = handler
    }

    func take(forIdentifier identifier: String) -> (() -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handlers.removeValue(forKey: identifier)
    }
}
