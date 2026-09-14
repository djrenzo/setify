import SwiftUI

@MainActor
struct EpisodesListView: View {
    let title: String
    let model: AppModel

    @State private var store: EpisodeCatalogStore

    init(title: String, collectionID: String, model: AppModel) {
        self.title = title
        self.model = model
        _store = State(initialValue: EpisodeCatalogStore(service: model.catalog.episodeCatalog, collectionID: collectionID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.episodes) { episode in
                    EpisodeRow(card: episode) {
                        model.playback.prepare(.video(episode))
                    }
                    .task {
                        if episode.id == store.episodes.last?.id {
                            store.loadNextPage()
                        }
                    }
                }
            }
            .padding(18)
            if store.isLoading {
                ProgressView().padding()
            }
            if let message = store.errorMessage, store.episodes.isEmpty {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(message))
                    .padding(.top, 60)
            }
        }
        .background(Color.cinemaBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { store.loadInitial() }
    }
}

struct EpisodeRow: View {
    let card: MediaCard
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title).font(.headline).lineLimit(2)
                    if let subtitle = card.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let duration = card.duration {
                        Label(duration, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.cinemaAccent)
            }
            .padding(12)
            .contentShape(.rect)
            .cinemaCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reproducir \(card.title)")
    }

    private var artwork: some View {
        AsyncImage(url: card.artworkURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.cinemaSurfaceRaised
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 116, height: 72)
        .clipShape(.rect(cornerRadius: 12))
    }
}
