import Foundation

enum CatalogCategory: String, CaseIterable, Identifiable, Hashable {
    case programas
    case series
    case miniseries
    case peliculas

    var id: Self { self }

    var title: String {
        switch self {
        case .programas: "Programas"
        case .series: "Series"
        case .miniseries: "Miniseries"
        case .peliculas: "Películas"
        }
    }

    var icon: String {
        switch self {
        case .programas: "tv.fill"
        case .series: "play.tv.fill"
        case .miniseries: "rectangle.stack.fill"
        case .peliculas: "film.fill"
        }
    }
}

struct ShowSummary: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let posterURL: URL?
}

struct Season: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct EpisodeCollection: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct FlatCatalogItem: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let posterURL: URL?
    let pageURL: URL
}

struct MiniserieShow: Hashable, Identifiable, Sendable {
    let id: String
    let tag: String
    let title: String
    let posterURL: URL?
}

struct MiniserieEpisode: Hashable, Identifiable, Sendable {
    let id: String
    let seasonTitle: String?
    let title: String
    let subtitle: String?
    let overview: String?
    let thumbnailURL: URL?
    let pageURL: URL
}

struct CursorPage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?
}

struct NumberedPage<Item: Sendable>: Sendable {
    let items: [Item]
    let currentPage: Int
    let totalPages: Int
}
