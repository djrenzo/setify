import UIKit

/// UIKit only lets an app force a specific interface orientation through the app delegate's
/// `supportedInterfaceOrientationsFor` hook plus `UIWindowScene.requestGeometryUpdate` — there is
/// no SwiftUI-native equivalent, so this small delegate exists purely to back that hook.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

@MainActor
enum OrientationController {
    static func apply(_ orientation: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = orientation
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
    }
}
