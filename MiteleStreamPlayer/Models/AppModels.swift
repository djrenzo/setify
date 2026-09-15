import Foundation

struct Channel: Codable, Hashable, Identifiable, Sendable {
    enum Source: String, Codable, CaseIterable, Sendable {
        case mediaset
        case direct

        var title: String {
            switch self {
            case .mediaset: "Mediaset"
            case .direct: "HLS directo"
            }
        }
    }

    enum HeaderProfile: String, Codable, CaseIterable, Sendable {
        case mediaset
        case rtve
        case none

        var title: String {
            switch self {
            case .mediaset: "Mediaset"
            case .rtve: "RTVE"
            case .none: "Sin cabeceras"
            }
        }
    }

    let id: UUID
    var name: String
    var shortName: String
    var source: Source
    var slug: String?
    var directURL: URL?
    var headerProfile: HeaderProfile
    var isEnabled: Bool
    var tintHex: String

    /// Known channels double as their real-world channel number in Spain, so a plain SF Symbol
    /// numeral badge reads as a proper channel icon without needing any bundled logo artwork.
    /// Custom channels the user adds fall back to a generic TV glyph.
    var iconSymbolName: String {
        switch (slug ?? shortName).lowercased() {
        case "telecinco", "t5": "5.circle.fill"
        case "cuatro": "4.circle.fill"
        case "la1", "1": "1.circle.fill"
        case "la2", "2": "2.circle.fill"
        default: "tv.fill"
        }
    }
}

struct MediaCard: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let detail: String?
    let duration: String?
    let artworkURL: URL?
    let pageURL: URL
}

enum PlaybackRequest: Sendable {
    case channel(Channel)
    case video(MediaCard)
    /// A previously downloaded item, already resolved to its local file — no network resolution
    /// needed, unlike `.video`.
    case downloaded(ResolvedStream)
}

struct SubtitleTrack: Hashable, Sendable {
    let url: URL
    let languageTag: String
}

struct ResolvedStream: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let url: URL
    let headers: [String: String]
    let allowsHeaderFallback: Bool
    let subtitles: [SubtitleTrack]
    let artworkURL: URL?
    let isLive: Bool
    /// The catalog item's stable id (`MediaCard.id`) — used to save/resume watch progress.
    /// `nil` for live channels, which aren't resumable.
    let contentID: String?
}

struct WatchProgress: Codable, Hashable, Sendable {
    let contentID: String
    var positionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date

    var fraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }
}

enum PreparationPhase: Sendable, Equatable {
    case resolvingMetadata
    case authorizing
    case loadingPlayer

    var title: String {
        switch self {
        case .resolvingMetadata: "Localizando la señal"
        case .authorizing: "Autorizando la reproducción"
        case .loadingPlayer: "Abriendo el reproductor"
        }
    }

    var detail: String {
        switch self {
        case .resolvingMetadata: "Consultando la información del contenido…"
        case .authorizing: "Creando un enlace temporal para esta sesión…"
        case .loadingPlayer: "Preparando el vídeo y sus controles…"
        }
    }
}

enum PlaybackFailure: Error, Sendable {
    case missingCredentials
    case sessionExpired
    case apiChanged
    case unavailableClearStream
    case invalidChannel
    case invalidURL
    case network
    case playback

    var title: String {
        switch self {
        case .missingCredentials: "Falta la sesión"
        case .sessionExpired: "La sesión ha caducado"
        case .apiChanged: "El servicio ha cambiado"
        case .unavailableClearStream: "Contenido no compatible"
        case .invalidChannel: "Canal no válido"
        case .invalidURL: "Enlace no válido"
        case .network: "Sin conexión con el servicio"
        case .playback: "No se puede reproducir"
        }
    }

    var message: String {
        switch self {
        case .missingCredentials:
            "Abre Sesión del prototipo y pega tus valores GMID y COOKIE."
        case .sessionExpired:
            "Actualiza los valores GMID y COOKIE desde Sesión del prototipo."
        case .apiChanged:
            "La respuesta ya no tiene el formato esperado. Este acceso privado puede cambiar sin aviso."
        case .unavailableClearStream:
            "Esta señal solo ofrece una variante protegida y el prototipo no implementa FairPlay."
        case .invalidChannel:
            "Revisa el slug o la dirección del canal en Gestionar canales."
        case .invalidURL:
            "El servicio devolvió una dirección que no se puede abrir."
        case .network:
            "Comprueba tu conexión, región y disponibilidad del servicio e inténtalo de nuevo."
        case .playback:
            "La señal respondió, pero AVPlayer no pudo iniciar el vídeo."
        }
    }
}

struct PrototypeCredentials: Equatable, Sendable {
    let gmid: String
    let cookie: String

    var isValid: Bool {
        !gmid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
