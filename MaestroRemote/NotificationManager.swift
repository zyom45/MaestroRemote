import UserNotifications
import Foundation

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let categoryID = "PERMISSION_REQUEST"
    private var notifiedIDs: Set<UUID> = []

    weak var client: MaestroClient?

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        registerCategory()
        requestPermission()
    }

    private func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func registerCategory() {
        let noAction         = UNNotificationAction(identifier: "no",             title: "✕ No",            options: [.destructive])
        let yesAction        = UNNotificationAction(identifier: "yes",            title: "✓ Yes",           options: [])
        let dontAskAction    = UNNotificationAction(identifier: "dont_ask_again", title: "Don't Ask Again", options: [])
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [noAction, yesAction, dontAskAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Background: fire notifications for all pending permissions

    /// バックグラウンド移行時に呼ぶ。notifiedIDs をリセットして全件通知する。
    func notifyAllPending(_ permissions: [MaestroClient.Permission], baseURL: String) {
        notifiedIDs.removeAll()
        let total = permissions.count
        for perm in permissions {
            scheduleNotification(for: perm, baseURL: baseURL, badge: total)
        }
    }

    /// 個別に通知（ポーリング中の新着用。フォアグラウンドでは willPresent が抑制する）
    func notify(for permission: MaestroClient.Permission, baseURL: String) {
        guard !notifiedIDs.contains(permission.id) else { return }
        scheduleNotification(for: permission, baseURL: baseURL, badge: 1)
    }

    private func scheduleNotification(for permission: MaestroClient.Permission, baseURL: String, badge: Int) {
        notifiedIDs.insert(permission.id)

        let content = UNMutableNotificationContent()
        content.title              = "\(permission.toolEmoji) \(permission.toolName)"
        content.subtitle           = permission.projectName
        content.body               = permission.primaryArg.isEmpty ? permission.label : permission.primaryArg
        content.sound              = .default
        content.badge              = NSNumber(value: badge)
        content.categoryIdentifier = categoryID
        content.userInfo           = [
            "permissionID": permission.id.uuidString,
            "baseURL": baseURL
        ]

        let request = UNNotificationRequest(
            identifier: permission.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Foreground: clear notifications and reset state

    /// フォアグラウンド復帰時に呼ぶ。通知センターとバッジをリセット。
    func cancelAllAndResetBadge() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        notifiedIDs.removeAll()
    }

    /// 個別キャンセル（アプリ内で応答したとき）
    func cancelNotification(for id: UUID) {
        let str = id.uuidString
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [str])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [str])
        notifiedIDs.remove(id)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// フォアグラウンド中は通知バナーを抑制（アプリ内カードUIで表示するため）
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    /// 通知のアクションボタン（No / Yes / Don't Ask Again）をタップしたとき
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard
            let idStr   = userInfo["permissionID"] as? String,
            let id      = UUID(uuidString: idStr),
            let baseURL = userInfo["baseURL"] as? String
        else { completionHandler(); return }

        let action: String
        switch response.actionIdentifier {
        case "no":              action = "no"
        case "yes":             action = "yes"
        case "dont_ask_again":  action = "dont_ask_again"
        default:
            // 通知本体タップ → アプリをフォアグラウンドに出すだけ
            completionHandler(); return
        }

        Task {
            await Self.sendResponse(id: id, action: action, baseURL: baseURL)
            await MainActor.run {
                NotificationManager.shared.client?.pendingPermissions.removeAll { $0.id == id }
                NotificationManager.shared.cancelNotification(for: id)
            }
            completionHandler()
        }
    }

    private static func sendResponse(id: UUID, action: String, baseURL: String) async {
        guard let url = URL(string: "\(baseURL)/respond") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["id": id.uuidString, "action": action]
        )
        _ = try? await URLSession.shared.data(for: req)
    }
}
