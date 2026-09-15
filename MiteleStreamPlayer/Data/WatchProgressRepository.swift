import Foundation
import Observation

protocol WatchProgressRepository: Sendable {
    func load() async throws -> [String: WatchProgress]
    func save(_ progress: [String: WatchProgress]) async throws
}

actor JSONWatchProgressRepository: WatchProgressRepository {
    private let fileManager: FileManager
    private let fileName = "watch_progress.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() async throws -> [String: WatchProgress] {
        let destination = try destinationURL()
        guard fileManager.fileExists(atPath: destination.path) else { return [:] }
        let data = try Data(contentsOf: destination)
        return try JSONDecoder().decode([String: WatchProgress].self, from: data)
    }

    func save(_ progress: [String: WatchProgress]) async throws {
        let destination = try destinationURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(progress)
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
final class WatchProgressStore {
    private let repository: any WatchProgressRepository
    private var isLoaded = false

    private(set) var progress: [String: WatchProgress] = [:]

    init(repository: any WatchProgressRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        isLoaded = true
        progress = (try? await repository.load()) ?? [:]
    }

    func progress(for contentID: String) -> WatchProgress? {
        progress[contentID]
    }

    func fraction(for contentID: String) -> Double {
        progress[contentID]?.fraction ?? 0
    }

    /// Saves the current position, unless the video is barely started or effectively finished —
    /// in both cases there's nothing useful to resume, so any existing entry is cleared instead.
    func update(contentID: String, position: Double, duration: Double) async {
        guard position.isFinite, duration.isFinite, duration > 30 else { return }
        let fraction = position / duration
        if fraction >= 0.95 || position < 10 {
            guard progress.removeValue(forKey: contentID) != nil else { return }
        } else {
            progress[contentID] = WatchProgress(
                contentID: contentID,
                positionSeconds: position,
                durationSeconds: duration,
                updatedAt: .now
            )
        }
        await persist()
    }

    private func persist() async {
        try? await repository.save(progress)
    }
}
