import SwiftUI

struct LiveChannelList: View {
    let store: ChannelStore
    let onPlay: (Channel) -> Void
    let onManage: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading) {
            sectionHeader
            content
        }
        .padding(.top, 8)
    }

    private var sectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ahora en directo").font(.title3.bold())
                Text("Toca una señal para prepararla").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Gestionar", action: onManage)
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            ProgressView("Cargando canales…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if let message = store.errorMessage, store.channels.isEmpty {
            ContentUnavailableView(
                "Catálogo no disponible",
                systemImage: "tv.slash",
                description: Text(message)
            )
            .frame(minHeight: 220)
        } else if store.enabledChannels.isEmpty {
            ContentUnavailableView {
                Label("No hay canales activos", systemImage: "tv.badge.exclamationmark")
            } description: {
                Text("Activa o añade una señal desde Gestionar.")
            } actions: {
                Button("Gestionar canales", action: onManage)
                    .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 240)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.enabledChannels) { channel in
                    ChannelCard(channel: channel) { onPlay(channel) }
                }
            }
        }
    }
}

private struct ChannelCard: View {
    let channel: Channel
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    channelMark
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption.bold())
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.14), in: .circle)
                }
                Spacer(minLength: 22)
                liveBadge
                Text(channel.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(channel.source.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
            .background(cardBackground)
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay { cardBorder }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reproducir \(channel.name) en directo")
    }

    private var channelMark: some View {
        Image(systemName: channel.iconSymbolName)
            .font(.title2.weight(.bold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 46, height: 46)
            .background(.white.opacity(0.16), in: .rect(cornerRadius: 14))
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.cinemaAccent).frame(width: 6, height: 6)
            Text("EN DIRECTO")
        }
        .font(.caption2.bold())
        .tracking(0.7)
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: [Color(hex: channel.tintHex).opacity(0.76), Color.cinemaSurface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(.white.opacity(0.08), lineWidth: 1)
    }
}
