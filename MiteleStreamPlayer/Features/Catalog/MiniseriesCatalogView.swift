import SwiftUI

struct MiniserieRoute: Hashable {
    let show: MiniserieShow
}

@MainActor
struct MiniseriesCatalogView: View {
    @State var store: MiniseriesCatalogStore
    let model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.shows) { show in
                    NavigationLink(value: MiniserieRoute(show: show)) {
                        MiniserieTile(show: show)
                    }
                    .buttonStyle(.plain)
                    .task {
                        if show.id == store.shows.last?.id {
                            store.loadNextPage()
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            if store.isLoading {
                ProgressView().padding()
            }
            if let message = store.errorMessage, store.shows.isEmpty {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(message))
                    .padding(.top, 60)
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle("Miniseries")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MiniserieRoute.self) { route in
            MiniserieEpisodesView(show: route.show, model: model)
        }
        .task { store.loadInitial() }
    }
}

private struct MiniserieTile: View {
    let show: MiniserieShow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artwork
            Text(show.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
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
