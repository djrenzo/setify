import Foundation
import UserNotifications

/// Posts local notifications for download progress/completion so the user can tell a download is
/// still moving along even with the app backgrounded or the phone locked. Deliberately simple —
/// text-only progress in steps of 10%, not a live-updating progress bar (that would need a Live
/// Activity / widget extension, a much bigger addition).
@MainActor
enum DownloadNotifier {
    private static var hasRequestedAuthorization = false

    static func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func updateProgress(contentID: String, title: String, fraction: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Descargando"
        content.body = "\(title) — \(Int((fraction * 100).rounded()))%"
        post(identifier: progressIdentifier(for: contentID), content: content)
    }

    static func notifyFinished(contentID: String, title: String) {
        clearProgress(contentID: contentID)
        let content = UNMutableNotificationContent()
        content.title = "Descarga completada"
        content.body = title
        content.sound = .default
        post(identifier: "download-finished-\(contentID)", content: content)
    }

    static func notifyFailed(contentID: String, title: String) {
        clearProgress(contentID: contentID)
        let content = UNMutableNotificationContent()
        content.title = "No se pudo descargar"
        content.body = title
        content.sound = .default
        post(identifier: "download-failed-\(contentID)", content: content)
    }

    static func clearProgress(contentID: String) {
        let identifier = progressIdentifier(for: contentID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func post(identifier: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func progressIdentifier(for contentID: String) -> String {
        "download-progress-\(contentID)"
    }
}
