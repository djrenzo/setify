import SwiftUI

enum DiscoveryMode: String, CaseIterable, Identifiable {
    case live = "Directo"
    case search = "Buscar"

    var id: Self { self }
}

private enum HomeSheet: String, Identifiable {
    case credentials
    case channels

    var id: String { rawValue }
}

@MainActor
struct HomeView: View {
    let model: AppModel

    @State private var mode = DiscoveryMode.live
    @State private var sheet: HomeSheet?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.cinemaBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Señales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(for: CatalogCategory.self) { category in
                CategoryRootView(category: category, model: model)
            }
            .navigationDestination(for: ShowRoute.self) { route in
                showDetailDestination(for: route.show, favoriteKind: route.favoriteKind, model: model)
            }
        }
        .tint(Color.cinemaAccent)
        .sheet(item: $sheet, content: sheetContent)
        .task { await loadInitialState() }
        .onDisappear {
            model.search.cancel()
            model.playback.cancelPreparation()
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack {
                CategoryGridView(onSelect: { path.append($0) })
                modePicker
                if mode == .live {
                    LiveChannelList(
                        store: model.channels,
                        onPlay: playChannel,
                        onManage: { sheet = .channels }
                    )
                } else {
                    VODSearchView(
                        store: model.search,
                        favorites: model.favorites,
                        onPlay: playVideo,
                        onOpenShow: { show, kind in path.append(ShowRoute(show: show, favoriteKind: kind)) }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }

    private var modePicker: some View {
        Picker("Contenido", selection: $mode) {
            ForEach(DiscoveryMode.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 8)
        .accessibilityLabel("Tipo de contenido")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { sheet = .credentials } label: {
                Image(systemName: model.credentialStatus.hasCredentials ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
            }
            .accessibilityLabel("Sesiones de streaming")
        }
    }

    @ViewBuilder
    private func sheetContent(_ destination: HomeSheet) -> some View {
        switch destination {
        case .credentials:
            PrototypeSettingsView(vault: model.vault, atresVault: model.atresVault) {
                await model.credentialStatus.refresh()
                await model.playback.invalidateIdentity()
            }
        case .channels:
            ManageChannelsView(store: model.channels)
        }
    }

    private func loadInitialState() async {
        async let channels: Void = model.channels.load()
        async let credentials: Void = model.credentialStatus.refresh()
        _ = await (channels, credentials)
    }

    private func playChannel(_ channel: Channel) {
        model.playback.prepare(.channel(channel))
    }

    private func playVideo(_ card: MediaCard) {
        model.playback.prepare(.video(card))
    }
}
