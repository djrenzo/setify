import SwiftUI

struct VODSearchView: View {
    @Bindable var store: SearchStore
    let onPlay: (MediaCard) -> Void
    let onOpenShow: (ShowSummary) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 3) {
                Text("A la carta").font(.title3.bold())
                Text("Busca programas, series y películas de Mitele y Atresplayer").font(.caption).foregroundStyle(.secondary)
            }
            searchField
            resultContent
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Título del programa", text: $store.query)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.search)
                .onSubmit(store.submit)
            Button(action: store.submit) {
                Image(systemName: "arrow.right")
                    .font(.subheadline.bold())
                    .frame(width: 36, height: 36)
                    .background(Color.cinemaAccent, in: .circle)
                    .foregroundStyle(.white)
            }
            .disabled(store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Buscar")
        }
        .padding(12)
        .cinemaCard()
    }

    @ViewBuilder
    private var resultContent: some View {
        if store.isLoading {
            VStack {
                ProgressView().controlSize(.large).tint(Color.cinemaAccent)
                Text("Buscando…").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let message = store.errorMessage {
            ContentUnavailableView(
                "No se pudo buscar",
                systemImage: "wifi.exclamationmark",
                description: Text(message)
            )
            .frame(minHeight: 240)
        } else if store.hasSearched, store.results.isEmpty {
            ContentUnavailableView.search(text: store.query)
                .frame(minHeight: 240)
        } else if store.results.isEmpty {
            SearchInvitationView()
        } else {
            LazyVStack {
                ForEach(store.results) { result in
                    switch result {
                    case .show(let show):
                        ShowResultCard(show: show) { onOpenShow(show) }
                    case .playable(let card):
                        VODCard(card: card) { onPlay(card) }
                    }
                }
            }
        }
    }
}

private struct SearchInvitationView: View {
    var body: some View {
        VStack {
            ZStack {
                Circle().fill(Color.cinemaAccent.opacity(0.12)).frame(width: 92, height: 92)
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.cinemaAccent)
            }
            Text("Tu próxima historia empieza aquí").font(.headline)
            Text("Escribe un título y solo resolveremos la señal cuando pulses reproducir.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 290)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct VODCard: View {
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
                    metadata
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.cinemaAccent)
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

    private var metadata: some View {
        HStack(spacing: 8) {
            if let duration = card.duration {
                Label(duration, systemImage: "clock")
            }
            Text(card.id.isAtresID ? "ATRESPLAYER" : "MITELE").fontWeight(.bold).foregroundStyle(Color.cinemaAccent)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ShowResultCard: View {
    let show: ShowSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 5) {
                    Text(show.title).font(.headline).lineLimit(2)
                    if let subtitle = show.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(show.id.isAtresID ? "ATRESPLAYER" : "MITELE")
                        .font(.caption.bold())
                        .foregroundStyle(Color.cinemaAccent)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(.rect)
            .cinemaCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ver \(show.title)")
    }

    private var artwork: some View {
        AsyncImage(url: show.posterURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.cinemaSurfaceRaised
                    Image(systemName: "tv").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 116, height: 72)
        .clipShape(.rect(cornerRadius: 12))
    }
}
