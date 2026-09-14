import SwiftUI

@MainActor
struct RootTabView: View {
    let model: AppModel

    var body: some View {
        @Bindable var playback = model.playback
        TabView {
            HomeView(model: model)
                .tabItem { Label("Inicio", systemImage: "house.fill") }
            FavoritesView(model: model)
                .tabItem { Label("Favoritos", systemImage: "heart.fill") }
        }
        .tint(Color.cinemaAccent)
        .fullScreenCover(item: $playback.stream, onDismiss: model.playback.playerDismissed) {
            PlayerScreen(stream: $0)
        }
        .alert(item: $playback.presentedFailure, content: failureAlert)
        .overlay { preparationOverlay }
    }

    @ViewBuilder
    private var preparationOverlay: some View {
        if let phase = model.playback.phase {
            PreparationOverlay(phase: phase, onCancel: model.playback.cancelPreparation)
        }
    }

    private func failureAlert(_ item: PresentedFailure) -> Alert {
        Alert(
            title: Text(item.failure.title),
            message: Text(item.failure.message),
            dismissButton: .default(Text("Entendido"))
        )
    }
}
