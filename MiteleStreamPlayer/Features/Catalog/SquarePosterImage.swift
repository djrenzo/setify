import SwiftUI

/// A poster/thumbnail cropped to a perfect square, regardless of the source image's own aspect
/// ratio or of the flexible column width `LazyVGrid` hands it. Uses `GeometryReader` to pin an
/// explicit width/height before cropping, rather than relying on `AsyncImage` + `.aspectRatio`
/// negotiating an implicit size — that implicit approach let differently-shaped source images
/// (portrait posters vs. wide keyframe thumbnails) render as mismatched, overlapping rectangles.
struct SquarePosterImage: View {
    let url: URL?

    /// `AsyncImage` never retries a failed load on its own — if the very first attempt fails for
    /// any transient reason, it shows the placeholder forever until the view is recreated, which
    /// is exactly what a fresh app launch does (explaining "works after restart, not before").
    /// Changing this drives a fresh `AsyncImage` attempt via `.id(_:)`.
    @State private var retryCount = 0

    private let maxRetries = 3

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder.task { await scheduleRetry() }
                default:
                    placeholder
                }
            }
            .id(retryCount)
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 14))
    }

    private var placeholder: some View {
        ZStack {
            Color.cinemaSurfaceRaised
            Image(systemName: "film").foregroundStyle(.secondary)
        }
    }

    private func scheduleRetry() async {
        guard retryCount < maxRetries else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        retryCount += 1
    }
}
