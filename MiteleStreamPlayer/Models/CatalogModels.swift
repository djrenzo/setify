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
    let pageURL: URL
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

enum FavoriteKind: String, Codable, Sendable {
    case programa
    case serie
    case miniserie
    case pelicula
    case atresPrograma
    case atresSerie
    case atresPelicula

    var category: CatalogCategory {
        switch self {
        case .programa, .atresPrograma: .programas
        case .serie, .atresSerie: .series
        case .miniserie: .miniseries
        case .pelicula, .atresPelicula: .peliculas
        }
    }

    var isAtresplayer: Bool {
        switch self {
        case .atresPrograma, .atresSerie, .atresPelicula: true
        case .programa, .serie, .miniserie, .pelicula: false
        }
    }

    /// Maps a Mitele kind to its Atresplayer counterpart (used when favoriting from the
    /// Atresplayer side of a merged catalog tab); returns itself for kinds with no counterpart.
    var atresEquivalent: FavoriteKind {
        switch self {
        case .programa: .atresPrograma
        case .serie: .atresSerie
        case .pelicula: .atresPelicula
        case .atresPrograma, .atresSerie, .atresPelicula, .miniserie: self
        }
    }
}

/// A saved favorite. Carries just enough of the source item's fields to both display it in the
/// Favorites tab and reconstruct the original domain model (`ShowSummary`/`MiniserieShow`/
/// `MediaCard`) needed to navigate back into it or play it directly.
struct FavoriteItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let kind: FavoriteKind
    let refID: String
    let title: String
    let subtitle: String?
    let posterURL: URL?
    let pageURL: URL?
    let tag: String?

    init(show: ShowSummary, kind: FavoriteKind) {
        id = "\(kind.rawValue):\(show.id)"
        self.kind = kind
        refID = show.id
        title = show.title
        subtitle = show.subtitle
        posterURL = show.posterURL
        pageURL = nil
        tag = nil
    }

    init(miniserie show: MiniserieShow) {
        id = "\(FavoriteKind.miniserie.rawValue):\(show.id)"
        kind = .miniserie
        refID = show.id
        title = show.title
        subtitle = nil
        posterURL = show.posterURL
        pageURL = show.pageURL
        tag = show.tag
    }

    init(pelicula item: FlatCatalogItem, kind: FavoriteKind = .pelicula) {
        id = "\(kind.rawValue):\(item.id)"
        self.kind = kind
        refID = item.id
        title = item.title
        subtitle = nil
        posterURL = item.posterURL
        pageURL = item.pageURL
        tag = nil
    }

    var asShowSummary: ShowSummary? {
        guard kind == .programa || kind == .serie || kind == .atresPrograma || kind == .atresSerie else {
            return nil
        }
        return ShowSummary(id: refID, title: title, subtitle: subtitle, posterURL: posterURL)
    }

    var asMiniserieShow: MiniserieShow? {
        guard kind == .miniserie, let tag, let pageURL else { return nil }
        return MiniserieShow(id: refID, tag: tag, title: title, posterURL: posterURL, pageURL: pageURL)
    }

    var asMediaCard: MediaCard? {
        guard kind == .pelicula || kind == .atresPelicula, let pageURL else { return nil }
        return MediaCard(id: refID, title: title, subtitle: nil, detail: nil, duration: nil, artworkURL: posterURL, pageURL: pageURL)
    }
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

/// Atresplayer's row/search endpoints use 0-based page numbers and a plain `hasNext` boolean
/// (rather than Mediaset's 1-based `actualPage`/`totalPages`), so this mirrors that shape
/// directly instead of overloading `NumberedPage`'s different convention.
struct AtresPage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextPage: Int?
}
