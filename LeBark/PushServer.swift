import Foundation
import UserNotifications

// MARK: - 本地通知（仅用于提示「名单有更新」，不依赖 APNs，也不需要本地监听服务）

enum Notifier {
    static func requestAuth() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func push(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "乐币BARK" : title
        content.body = String(body.prefix(120))
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
