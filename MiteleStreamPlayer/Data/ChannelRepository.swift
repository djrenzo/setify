import Foundation
import Observation
import SwiftUI

protocol ChannelRepository: Sendable {
    func load() async throws -> [Channel]
    func save(_ channels: [Channel]) async throws
}

actor JSONChannelRepository: ChannelRepository {
    private let fileManager: FileManager
    private let bundle: Bundle
    private let fileName = "channels.json"

    init(fileManager: FileManager = .default, bundle: Bundle = .main) {
        self.fileManager = fileManager
        self.bundle = bundle
    }

    func load() async throws -> [Channel] {
        let destination = try destinationURL()
        if !fileManager.fileExists(atPath: destination.path) {
            let seed = try seedData()
            try seed.write(to: destination, options: [.atomic, .completeFileProtection])
        }
        let data = try Data(contentsOf: destination)
        return try JSONDecoder().decode([Channel].self, from: data)
    }

    func save(_ channels: [Channel]) async throws {
        let destination = try destinationURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(channels)
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

    private func seedData() throws -> Data {
        guard let url = bundle.url(forResource: "SeedChannels", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

@MainActor
@Observable
final class ChannelStore {
    private let repository: any ChannelRepository

    var channels: [Channel] = []
    var isLoading = true
    var errorMessage: String?

    var enabledChannels: [Channel] {
        channels.filter(\.isEnabled)
    }

    init(repository: any ChannelRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            channels = try await repository.load()
            errorMessage = nil
        } catch {
            channels = []
            errorMessage = "No se pudo abrir el catálogo local."
        }
    }

    func add(_ channel: Channel) async {
        channels.append(channel)
        await persist()
    }

    func delete(at offsets: IndexSet) async {
        channels.remove(atOffsets: offsets)
        await persist()
    }

    func move(from offsets: IndexSet, to destination: Int) async {
        channels.move(fromOffsets: offsets, toOffset: destination)
        await persist()
    }

    func setEnabled(_ enabled: Bool, for channelID: Channel.ID) async {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else { return }
        channels[index].isEnabled = enabled
        await persist()
    }

    private func persist() async {
        do {
            try await repository.save(channels)
            errorMessage = nil
        } catch {
            errorMessage = "No se pudieron guardar los cambios."
        }
    }
}