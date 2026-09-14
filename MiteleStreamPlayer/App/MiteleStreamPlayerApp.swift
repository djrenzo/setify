import SwiftUI

@main
@MainActor
struct MiteleStreamPlayerApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
