import SwiftUI

@main
@MainActor
struct MiteleStreamPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootTabView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
