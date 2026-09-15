import Foundation

/// Atresplayer content is resolved completely differently from Mitele's (no "programme page URL"
/// to resolve — just a raw `contentId` fed straight to a player endpoint), but `MediaCard`/
/// `FlatCatalogItem` only carry a `pageURL` as their "how to resolve this" field. Rather than
/// adding a `source` field that ripples through every model, view and store that touches these
/// generic types, an Atres item's `pageURL` encodes its id in a private `atresplayer://` scheme —
/// opaque to the UI (which never inspects it), understood only by the resolver.
enum AtresContentRef: Sendable {
    case episode(String)
    case recording(String)
    /// "Todas las películas" cards are FORMAT-shaped (a `formatId`, `monoChapter: true`, no
    /// `seasons`) rather than flat RECORDING cards — see API_STREAM_RESOLUTION_ATRES.md §16 — so
    /// resolving one takes an extra lookup step the resolver handles (see `resolveMovie`).
    case movieFormat(String)

    private static let scheme = "atresplayer"

    var pageURL: URL {
        switch self {
        case .episode(let id):
            URL(string: "\(Self.scheme)://episode/\(id)")!
        case .recording(let id):
            URL(string: "\(Self.scheme)://recording/\(id)")!
        case .movieFormat(let id):
            URL(string: "\(Self.scheme)://movie/\(id)")!
        }
    }

    init?(pageURL url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let id = url.lastPathComponent
        guard !id.isEmpty else { return nil }
        switch url.host {
        case "episode": self = .episode(id)
        case "recording": self = .recording(id)
        case "movie": self = .movieFormat(id)
        default: return nil
        }
    }
}

extension String {
    private static let atresPrefix = "atres:"

    /// Atresplayer-sourced `ShowSummary`/`FlatCatalogItem` ids are namespaced with this prefix to
    /// avoid colliding with Mitele ids in the shared favorites/downloads/watch-progress stores,
    /// which key everything off one global `contentID` string.
    var isAtresID: Bool { hasPrefix(Self.atresPrefix) }

    var strippingAtresPrefix: String {
        isAtresID ? String(dropFirst(Self.atresPrefix.count)) : self
    }
}
