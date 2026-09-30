import Foundation
import Observation

protocol DRMProtectedRepository: Sendable {
    func load() async throws -> Set<String>
    func save(_ ids: Set<String>) async throws
}

actor JSONDRMProtectedRepository: DRMProtectedRepository {
    private let fileManager: FileManager
    private let fileName = "drm-protected.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() async throws -> Set<String> {
        let destination = try destinationURL()
        guard fileManager.fileExists(atPath: destination.path) else { return [] }
        let data = try Data(contentsOf: destination)
        return Set(try JSONDecoder().decode([String].self, from: data))
    }

    func save(_ ids: Set<String>) async throws {
        let destination = try destinationURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ids.sorted())
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

/// Remembers which catalog items (`MediaCard.id`) resolved to a FairPlay-only stream. There's no
/// cheap way to know this from a listing — it's only discovered when a stream is resolved — so it
/// gets recorded the first time an episode is played (or a download is attempted) and thereafter
/// drives the warning badge and the hidden download control in the episode lists.
@MainActor
@Observable
final class DRMRegistry {
    private let repository: any DRMProtectedRepository
    private var isLoaded = false
    private(set) var protectedIDs: Set<String> = []

    init(repository: any DRMProtectedRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        isLoaded = true
        protectedIDs = (try? await repository.load()) ?? []
    }

    func isProtected(_ contentID: String) -> Bool {
        protectedIDs.contains(contentID)
    }

    func mark(_ contentID: String) {
        guard !contentID.isEmpty, protectedIDs.insert(contentID).inserted else { return }
        let snapshot = protectedIDs
        Task { try? await repository.save(snapshot) }
    }
}
