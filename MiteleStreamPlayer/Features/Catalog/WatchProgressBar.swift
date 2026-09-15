import SwiftUI

/// A slim progress indicator overlaid on a thumbnail/artwork, showing how much of a VOD item has
/// already been watched. Renders nothing when there's no meaningful progress to show.
struct WatchProgressBar: View {
    let fraction: Double

    var body: some View {
        if fraction > 0 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.45)
                    Color.cinemaAccent.frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }
}
