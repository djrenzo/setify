import SwiftUI

/// A poster/thumbnail cropped to a perfect square, regardless of the source image's own aspect
/// ratio or of the flexible column width `LazyVGrid` hands it. Uses `GeometryReader` to pin an
/// explicit width/height before cropping, rather than relying on `AsyncImage` + `.aspectRatio`
/// negotiating an implicit size — that implicit approach let differently-shaped source images
/// (portrait posters vs. wide keyframe thumbnails) render as mismatched, overlapping rectangles.
struct SquarePosterImage: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    ZStack {
                        Color.cinemaSurfaceRaised
                        Image(systemName: "film").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 14))
    }
}
