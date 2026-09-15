import Foundation
import Observation

protocol DownloadsRepository: Sendable {
    func load() async throws -> [String: DownloadedItem]
    func save(_ downloads: [String: DownloadedItem]) async throws
}

actor JSONDownloadsRepository: DownloadsRepository {
    private let fileManager: FileManager
    private let fileName = "downloads.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() async throws -> [String: DownloadedItem] {
        let destination = try destinationURL()
        guard fileManager.fileExists(atPath: destination.path) else { return [:] }
        let data = try Data(contentsOf: destination)
        return try JSONDecoder().decode([String: DownloadedItem].self, from: data)
    }

    func save(_ downloads: [String: DownloadedItem]) async throws {
        let destination = try destinationURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(downloads)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
    }

    private func destinationURL() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("MiteleStreamPlayer", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }
}

@MainActor
@Observable
final class DownloadStore {
    private struct PendingDownload {
        let title: String
        let subtitle: String?
        let artworkURL: URL?
        var subtitlePath: String?
    }

    private let repository: any DownloadsRepository
    private let resolver: any StreamResolving
    private let engine: DownloadEngine
    private var isLoaded = false
    private var pending: [String: PendingDownload] = [:]
    private var lastNotifiedPercentBucket: [String: Int] = [:]

    private(set) var downloads: [String: DownloadedItem] = [:]
    private(set) var activeProgress: [String: Double] = [:]
    private(set) var failedIDs: Set<String> = []

    init(repository: any DownloadsRepository, resolver: any StreamResolving) {
        self.repository = repository
        self.resolver = resolver
        engine = DownloadEngine()

        engine.onProgress = { [weak self] contentID, fraction in
            Task { @MainActor in
                self?.activeProgress[contentID] = fraction
                self?.notifyProgressIfDue(contentID: contentID, fraction: fraction)
            }
        }
        engine.onFinished = { [weak self] contentID, location in
            Task { @MainActor in await self?.handleFinished(contentID: contentID, location: location) }
        }
        engine.onFailed = { [weak self] contentID, _ in
            Task { @MainActor in self?.handleFailed(contentID: contentID) }
        }
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        isLoaded = true
        downloads = (try? await repository.load()) ?? [:]
    }

    func state(for contentID: String) -> DownloadState {
        if downloads[contentID] != nil { return .downloaded }
        if let fraction = activeProgress[contentID] { return .downloading(progress: fraction) }
        if failedIDs.contains(contentID) { return .failed }
        return .notDownloaded
    }

    func startDownload(card: MediaCard) {
        let contentID = card.id
        guard downloads[contentID] == nil, activeProgress[contentID] == nil else { return }
        DownloadNotifier.requestAuthorizationIfNeeded()
        activeProgress[contentID] = 0
        failedIDs.remove(contentID)
        pending[contentID] = PendingDownload(
            title: card.title,
            subtitle: card.subtitle,
            artworkURL: card.artworkURL,
            subtitlePath: nil
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await resolver.resolve(.video(card)) { _ in }
                if let subtitleURL = stream.subtitles.first?.url {
                    let path = await downloadSubtitle(contentID: contentID, url: subtitleURL)
                    pending[contentID]?.subtitlePath = path
                }
                engine.startDownload(contentID: contentID, url: stream.url, headers: stream.headers, title: stream.title)
            } catch {
                handleFailed(contentID: contentID)
            }
        }
    }

    func cancelDownload(contentID: String) {
        engine.cancelDownload(contentID: contentID)
        pending.removeValue(forKey: contentID)
        activeProgress.removeValue(forKey: contentID)
        lastNotifiedPercentBucket.removeValue(forKey: contentID)
        DownloadNotifier.clearProgress(contentID: contentID)
    }

    func delete(contentID: String) async {
        guard let item = downloads.removeValue(forKey: contentID) else { return }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: item.bookmarkData, bookmarkDataIsStale: &isStale) {
            try? FileManager.default.removeItem(at: url)
        }
        if let subtitlePath = item.subtitlePath, let directory = try? subtitlesDirectory() {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(subtitlePath))
        }
        await persist()
    }

    /// Reconstructs a playable `ResolvedStream` pointing at the local downloaded file — no
    /// network headers needed since it's not a remote request anymore.
    func resolvedStream(for contentID: String) -> ResolvedStream? {
        guard let item = downloads[contentID] else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmarkData, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        var subtitles: [SubtitleTrack] = []
        if let subtitlePath = item.subtitlePath, let directory = try? subtitlesDirectory() {
            subtitles = [SubtitleTrack(url: directory.appendingPathComponent(subtitlePath), languageTag: "es")]
        }
        return ResolvedStream(
            title: item.title,
            url: url,
            headers: [:],
            allowsHeaderFallback: false,
            subtitles: subtitles,
            artworkURL: item.artworkURL,
            isLive: false,
            contentID: item.contentID
        )
    }

    private func handleFinished(contentID: String, location: URL) async {
        guard let metadata = pending.removeValue(forKey: contentID) else { return }
        activeProgress.removeValue(forKey: contentID)
        lastNotifiedPercentBucket.removeValue(forKey: contentID)
        guard let bookmark = try? location.bookmarkData() else {
            failedIDs.insert(contentID)
            DownloadNotifier.notifyFailed(contentID: contentID, title: metadata.title)
            return
        }
        downloads[contentID] = DownloadedItem(
            contentID: contentID,
            title: metadata.title,
            subtitle: metadata.subtitle,
            artworkURL: metadata.artworkURL,
            bookmarkData: bookmark,
            subtitlePath: metadata.subtitlePath,
            downloadedAt: .now
        )
        DownloadNotifier.notifyFinished(contentID: contentID, title: metadata.title)
        await persist()
    }

    private func handleFailed(contentID: String) {
        let title = pending.removeValue(forKey: contentID)?.title
        activeProgress.removeValue(forKey: contentID)
        lastNotifiedPercentBucket.removeValue(forKey: contentID)
        failedIDs.insert(contentID)
        DownloadNotifier.notifyFailed(contentID: contentID, title: title ?? "Descarga")
    }

    private func notifyProgressIfDue(contentID: String, fraction: Double) {
        guard let title = pending[contentID]?.title else { return }
        let bucket = Int((fraction * 100).rounded()) / 10
        guard lastNotifiedPercentBucket[contentID] != bucket else { return }
        lastNotifiedPercentBucket[contentID] = bucket
        DownloadNotifier.updateProgress(contentID: contentID, title: title, fraction: fraction)
    }

    private func downloadSubtitle(contentID: String, url: URL) async -> String? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let directory = try subtitlesDirectory()
            let filename = "\(contentID).vtt"
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    private func subtitlesDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("MiteleStreamPlayer", isDirectory: true)
            .appendingPathComponent("DownloadedSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func persist() async {
        try? await repository.save(downloads)
    }
}
