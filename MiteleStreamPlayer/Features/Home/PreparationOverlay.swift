import SwiftUI

struct PreparationOverlay: View {
    let phase: PreparationPhase
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.64).ignoresSafeArea()
            VStack {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 8)
                    Circle()
                        .trim(from: 0.08, to: 0.76)
                        .stroke(Color.cinemaAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "play.fill").foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(phase == .authorizing ? 16 : 0))
                .animation(.spring(response: 0.5), value: phase)
                Text(phase.title).font(.title3.bold())
                Text(phase.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.bordered)
            }
            .padding(28)
            .frame(maxWidth: 330)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.1))
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(phase.title). \(phase.detail)")
    }
}

