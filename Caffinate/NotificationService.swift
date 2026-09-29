import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    var isEnabled = true
    private var pending: (title: String, body: String)?

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        if let pending {
            self.pending = nil
            deliver(title: pending.title, body: pending.body)
        }
    }

    func send(title: String, body: String) {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                guard let self else { return }
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.deliver(title: title, body: body)
                case .notDetermined:
                    self.pending = (title, body)
                    await self.requestPermission()
                default:
                    break
                }
            }
        }
    }

    private func deliver(title: String, body: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
