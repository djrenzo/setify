import SwiftUI

@MainActor
struct RootTabView: View {
    let model: AppModel

    var body: some View {
        @Bindable var playback = model.playback
        TabView {
            HomeView(model: model)
                .safeAreaInset(edge: .bottom) { nowPlayingBar }
                .tabItem { Label("Inicio", systemImage: "house.fill") }
            DownloadsView(model: model)
                .safeAreaInset(edge: .bottom) { nowPlayingBar }
                .tabItem { Label("Descargas", systemImage: "arrow.down.circle.fill") }
            FavoritesView(model: model)
                .safeAreaInset(edge: .bottom) { nowPlayingBar }
                .tabItem { Label("Favoritos", systemImage: "heart.fill") }
        }
        .tint(Color.cinemaAccent)
        .animation(.snappy, value: model.playback.session.map(ObjectIdentifier.init))
        .animation(.snappy, value: model.playback.isPlayerExpanded)
        .fullScreenCover(isPresented: $playback.isPlayerExpanded, onDismiss: model.playback.playerCoverDismissed) {
            if let session = model.playback.session {
                PlayerScreen(
                    session: session,
                    onMinimize: model.playback.minimizePlayer,
                    onClose: model.playback.closePlayer
                )
            }
        }
        .alert(item: $playback.presentedFailure, content: failureAlert)
        .overlay { preparationOverlay }
    }

    /// Inset into each tab's content (rather than overlaid on the whole `TabView`) so it sits
    /// directly above the tab bar and scrollable content isn't hidden behind it.
    @ViewBuilder
    private var nowPlayingBar: some View {
        if let session = model.playback.session, !model.playback.isPlayerExpanded {
            NowPlayingBar(
                session: session,
                onExpand: model.playback.expandPlayer,
                onClose: model.playback.closePlayer
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
