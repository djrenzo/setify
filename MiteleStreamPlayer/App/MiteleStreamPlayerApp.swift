import SwiftUI

@main
@MainActor
struct MiteleStreamPlayerApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootTabView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
