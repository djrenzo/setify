import Foundation
import Observation

/// An in-app, copyable trace of the FairPlay exchange so a DRM playback failure can be diagnosed
/// without attaching Xcode. `FairPlayContentKeyDelegate` records each step here (in addition to
/// `os.Logger`), and the player's failure overlay shows and copies it.
@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private(set) var lines: [String] = []

    /// The whole log as one string, ready for the clipboard.
    var text: String { lines.joined(separator: "\n") }

    var isEmpty: Bool { lines.isEmpty }

    func clear() { lines = [] }

    private func add(_ message: String) {
        let stamp = Self.formatter.string(from: .now)
        lines.append("[\(stamp)] \(message)")
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
    }

    /// Callable from any thread — the FairPlay delegate runs off the main actor.
    nonisolated static func record(_ message: String) {
        Task { @MainActor in shared.add(message) }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
