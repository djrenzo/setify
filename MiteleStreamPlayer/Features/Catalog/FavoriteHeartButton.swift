import SwiftUI

struct FavoriteHeartButton: View {
    let isFavorite: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isFavorite ? Color.cinemaAccent : .white)
                .padding(8)
                .background(.black.opacity(0.45), in: .circle)
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel(isFavorite ? "Quitar de favoritos" : "Añadir a favoritos")
    }
}
