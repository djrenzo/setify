import SwiftUI

struct ShowRoute: Hashable {
    let show: ShowSummary
}

struct ShowGridView: View {
    let shows: [ShowSummary]
    let isLoading: Bool
    let errorMessage: String?
    let onReachEnd: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(shows) { show in
                    NavigationLink(value: ShowRoute(show: show)) {
                        ShowTile(show: show)
                    }
                    .buttonStyle(.plain)
                    .task {
                        if show.id == shows.last?.id {
                            onReachEnd()
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            if isLoading {
                ProgressView().padding()
            }
            if let errorMessage, shows.isEmpty {
                ContentUnavailableView(
                    "No se pudo cargar",
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
                .padding(.top, 60)
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
    }
}

private struct ShowTile: View {
    let show: ShowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artwork
            Text(show.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
            if let subtitle = show.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var artwork: some View {
        AsyncImage(url: show.posterURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.cinemaSurfaceRaised
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 14))
    }
}
