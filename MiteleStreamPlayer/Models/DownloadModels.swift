import Foundation

struct DownloadedItem: Codable, Hashable, Identifiable, Sendable {
    var id: String { contentID }
    let contentID: String
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    /// Resolves to the local `.movpkg` bundle AVAssetDownloadTask saved — its exact path can
    /// change between launches, so a bookmark is stored rather than a raw URL/path string.
    let bookmarkData: Data
    /// Filename (not full path) of the locally saved WebVTT sidecar, if the source had one.
    let subtitlePath: String?
    let downloadedAt: Date
}

enum DownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed
}
