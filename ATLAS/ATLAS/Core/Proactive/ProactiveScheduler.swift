import Foundation
import UserNotifications

/// Proaktive Unterstützung über lokale Mitteilungen.
///
/// Ehrlich zu den Grenzen von iOS: Eine App darf nicht dauerhaft im Hintergrund
/// arbeiten. ATLAS plant deshalb zur gewünschten Uhrzeit eine Mitteilung. Tippen
/// Sie darauf, öffnet sich ATLAS und erstellt die Übersicht sofort mit aktuellen Daten.
@MainActor
enum ProactiveScheduler {
    private static let morningID = "atlas.briefing.morning"
    private static let eveningID = "atlas.briefing.evening"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Plant (oder entfernt) die täglichen Mitteilungen gemäß den Einstellungen.
    static func reschedule(settings: AppSettings) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningID, eveningID])
        guard settings.morningBriefingEnabled || settings.eveningReviewEnabled else { return }
        guard await requestAuthorization() else { return }

        if settings.morningBriefingEnabled {
            await add(id: morningID, kind: .morning, minutes: settings.morningBriefingMinutes,
                      title: "Guten Morgen\(settings.sirSuffix).",
                      body: "Ihre Tagesübersicht ist bereit. Tippen Sie hier, und ATLAS fasst Ihren Tag zusammen.")
        }
        if settings.eveningReviewEnabled {
            await add(id: eveningID, kind: .evening, minutes: settings.eveningReviewMinutes,
                      title: "Ihr Tagesrückblick",
                      body: "Offene Aufgaben und die Termine von morgen – tippen Sie hier.")
        }
    }

    private static func add(id: String, kind: BriefingKind, minutes: Int, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["briefing": kind.rawValue]

        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// Reagiert auf das Antippen einer ATLAS-Mitteilung.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["briefing"] as? String
        if let raw, let kind = BriefingKind(rawValue: raw) {
            Task { @MainActor in IntentRouter.shared.request(.briefing(kind)) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
