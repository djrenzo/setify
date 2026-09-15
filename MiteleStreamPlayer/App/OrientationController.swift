import UIKit
import UserNotifications

/// UIKit only lets an app force a specific interface orientation through the app delegate's
/// `supportedInterfaceOrientationsFor` hook plus `UIWindowScene.requestGeometryUpdate` — there is
/// no SwiftUI-native equivalent. This same app delegate also backs background download
/// completion (`handleEventsForBackgroundURLSession`) and shows local notifications while the
/// app is in the foreground, since none of that has a SwiftUI-native hook either.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    /// Called when iOS relaunches the app in the background because a background `URLSession`
    /// (the download session) finished work while the app wasn't running. The completion handler
    /// must be called once that session's delegate has finished processing its queued events —
    /// stored here since `DownloadEngine` (which owns that session) may not exist yet at this
    /// point in the launch sequence.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadCompletionRegistry.shared.store(completionHandler, forIdentifier: identifier)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Without this, local notifications (download progress/completion) are silently suppressed
    /// while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
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
