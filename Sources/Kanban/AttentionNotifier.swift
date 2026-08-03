import AppKit
import UserNotifications

/// Signals that a ticket's Claude console is waiting for an answer. Combines several delivery paths
/// for robustness on an ad-hoc-signed dev app:
///   • Dock icon bounce + red badge (permission-free, always works),
///   • `UNUserNotificationCenter` banner (shows as "Kanban" when it works),
///   • `osascript` banner fallback (shows as "Script Editor"; needs that app's notifications enabled).
@MainActor
final class AttentionNotifier: NSObject {
    static let shared = AttentionNotifier()

    private var onSelect: ((String) -> Void)?
    private var lastPosted: [String: Date] = [:]

    func configure(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A ticket started waiting: bounce the Dock, then post a banner (throttled per ticket).
    func post(ticketKey: String, summary: String?) {
        NSApp.requestUserAttention(.informationalRequest)
        guard lastPosted[ticketKey].map({ Date().timeIntervalSince($0) >= 30 }) ?? true else { return }
        lastPosted[ticketKey] = Date()
        deliver(title: "\(ticketKey) hat eine Frage",
                body: summary ?? "Die Claude-Console wartet auf eine Antwort.",
                ticketKey: ticketKey)
    }

    /// Single delivery path: UNUserNotificationCenter under the app's identity when bundled,
    /// osascript only as a fallback for `swift run` (no bundle). Avoids duplicate banners.
    private func deliver(title: String, body: String, ticketKey: String?) {
        if Bundle.main.bundleIdentifier != nil {
            deliverUN(title: title, body: body, ticketKey: ticketKey)
        } else {
            deliverOsascript(title: title, body: body)
        }
    }

    /// Reflects the number of waiting tickets as a red Dock badge (nil clears it).
    func updateBadge(count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    /// Settings "Test" button: fire ALL paths so it's clear which one surfaces on this machine.
    /// The Dock badge is set immediately (visible even while the app is active) as proof of life;
    /// requestUserAttention only bounces when the app is in the background.
    func sendTest() {
        NSApp.dockTile.badgeLabel = "TEST"
        NSApp.requestUserAttention(.criticalRequest)
        deliver(title: "Kanban-Test", body: "Wenn du das als Banner siehst, ist alles korrekt eingestellt.",
                ticketKey: nil)
    }

    /// Human-readable UN authorization status, for the settings diagnostic label.
    func authorizationStatusText() async -> String {
        guard Bundle.main.bundleIdentifier != nil else { return "kein App-Bundle" }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:    return "erlaubt"
        case .denied:        return "verweigert (Systemeinstellungen → Mitteilungen → Kanban)"
        case .notDetermined: return "noch nicht gefragt"
        case .provisional:   return "provisorisch"
        case .ephemeral:     return "ephemeral"
        @unknown default:    return "unbekannt"
        }
    }

    func clearThrottle(ticketKey: String) { lastPosted[ticketKey] = nil }

    // MARK: - Delivery paths

    private func deliverUN(title: String, body: String, ticketKey: String?) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let ticketKey { content.userInfo = ["ticket": ticketKey] }
        let id = ticketKey.map { "attention-\($0)" } ?? "kanban-test"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func deliverOsascript(title: String, body: String) {
        let script = "display notification \"\(Self.escape(body))\" "
            + "with title \"\(Self.escape(title))\" sound name \"Submarine\""
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

extension AttentionNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let ticket = response.notification.request.content.userInfo["ticket"] as? String
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if let ticket { AttentionNotifier.shared.onSelect?(ticket) }
        }
        completionHandler()
    }
}
