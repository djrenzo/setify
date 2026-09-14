import Foundation
import Observation

protocol FavoritesRepository: Sendable {
    func load() async throws -> [FavoriteItem]
    func save(_ favorites: [FavoriteItem]) async throws
}

actor JSONFavoritesRepository: FavoritesRepository {
    private let fileManager: FileManager
    private let fileName = "favorites.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() async throws -> [FavoriteItem] {
        let destination = try destinationURL()
        guard fileManager.fileExists(atPath: destination.path) else { return [] }
        let data = try Data(contentsOf: destination)
        return try JSONDecoder().decode([FavoriteItem].self, from: data)
    }

    func save(_ favorites: [FavoriteItem]) async throws {
        let destination = try destinationURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(favorites)
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
final class FavoritesStore {
    private let repository: any FavoritesRepository

    var favorites: [FavoriteItem] = []
    var isLoading = true
    var errorMessage: String?

    init(repository: any FavoritesRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            favorites = try await repository.load()
            errorMessage = nil
        } catch {
            favorites = []
            errorMessage = "No se pudieron cargar los favoritos."
        }
    }

    func isFavorite(_ id: String) -> Bool {
        favorites.contains { $0.id == id }
    }

    func toggle(_ item: FavoriteItem) async {
        if let index = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: index)
        } else {
            favorites.append(item)
        }
        await persist()
    }

    func remove(_ item: FavoriteItem) async {
        favorites.removeAll { $0.id == item.id }
        await persist()
    }

    private func persist() async {
        do {
            try await repository.save(favorites)
            errorMessage = nil
        } catch {
            errorMessage = "No se pudieron guardar los favoritos."
        }
    }
}
