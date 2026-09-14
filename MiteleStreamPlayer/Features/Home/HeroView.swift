import SwiftUI

struct HeroView: View {
    let liveCount: Int
    let hasCredentials: Bool
    let onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            heroTop
            Text("Televisión en directo y contenidos a la carta, en una sola señal privada.")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            statusRow
        }
        .padding(22)
        .background(heroBackground)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .overlay { heroBorder }
        .padding(.top, 8)
    }

    private var heroTop: some View {
        HStack {
            Label("MITELE LAB", systemImage: "sparkles")
                .font(.caption.bold())
                .tracking(1.2)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.12), in: .capsule)
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2.weight(.semibold))
                .symbolEffect(.pulse, options: .repeating)
        }
        .foregroundStyle(.white)
    }

    private var statusRow: some View {
        HStack {
            HeroMetric(value: "\(liveCount)", label: "directos", icon: "play.tv.fill")
            Divider().overlay(.white.opacity(0.2)).frame(height: 34)
            Button(action: onConfigure) {
                HeroMetric(
                    value: hasCredentials ? "Lista" : "Pendiente",
                    label: "sesión",
                    icon: hasCredentials ? "checkmark.seal.fill" : "key.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre la configuración de la sesión")
        }
        .padding(.top, 6)
    }

    private var heroBackground: some View {
        LinearGradient(
            colors: [Color.cinemaAccent, Color(hex: "9E2338"), Color.cinemaSurface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var heroBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(.white.opacity(0.14), lineWidth: 1)
    }
}

private struct HeroMetric: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.subheadline.bold())
                Text(label).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
