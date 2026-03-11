import UserNotifications
import Foundation

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let categoryID = "PERMISSION_REQUEST"
    private var notifiedIDs: Set<UUID> = []

    /// バックグラウンド中かどうか（fetchPending での即時通知判定に使用）
    var isInBackground: Bool = false

    /// 接続中の Mac への baseURL（トークン送信に使用）
    weak var client: MaestroClient?

    /// APNs デバイストークン
    private(set) var deviceToken: String? = UserDefaults.standard.string(forKey: "apns.deviceToken")

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
        let noAction      = UNNotificationAction(identifier: "no",             title: "✕ No",            options: [.destructive])
        let yesAction     = UNNotificationAction(identifier: "yes",            title: "✓ Yes",           options: [])
        let dontAskAction = UNNotificationAction(identifier: "dont_ask_again", title: "Don't Ask Again", options: [])
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [noAction, yesAction, dontAskAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - APNs Device Token

    /// AppDelegate から呼ばれる。トークンを保存して Mac へ送信する。
    func didReceiveDeviceToken(_ token: String) async {
        deviceToken = token
        UserDefaults.standard.set(token, forKey: "apns.deviceToken")
        if let baseURL = client?.baseURL, !baseURL.isEmpty {
            await sendTokenToMac(token: token, baseURL: baseURL)
        }
    }

    /// 接続確立時（baseURL 設定後）に保存済みトークンを Mac へ送る。
    func sendStoredTokenIfNeeded(baseURL: String) async {
        guard let token = deviceToken, !baseURL.isEmpty else { return }
        await sendTokenToMac(token: token, baseURL: baseURL)
    }

    private func sendTokenToMac(token: String, baseURL: String) async {
        guard let url = URL(string: "\(baseURL)/register-device") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceToken": token,
            "bundleId": "com.maestro.MaestroRemote",
            "notificationsEnabled": client?.notificationsEnabled ?? true
        ])
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Local Notification Fallback
    // APNs が未設定 / トークン未送信の間はローカル通知でカバー

    /// バックグラウンド移行時: 未通知の pending を即時発火
    func notifyAllPending(_ permissions: [MaestroClient.Permission], baseURL: String) {
        guard client?.notificationsEnabled != false else { return }
        let total = permissions.count
        for perm in permissions {
            scheduleLocalNotification(for: perm, baseURL: baseURL, badge: total)
        }
    }

    /// fetchPending() から呼ばれる（バックグラウンド中のみ）
    func notify(for permission: MaestroClient.Permission, baseURL: String) {
        guard client?.notificationsEnabled != false else { return }
        scheduleLocalNotification(for: permission, baseURL: baseURL, badge: 1)
    }

    private func scheduleLocalNotification(
        for permission: MaestroClient.Permission,
        baseURL: String,
        badge: Int
    ) {
        guard !notifiedIDs.contains(permission.id) else { return }
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

    /// ポーリングで解決済みと判明した permission の追跡IDを削除
    func cleanupResolvedIDs(_ activeIDs: Set<UUID>) {
        notifiedIDs = notifiedIDs.intersection(activeIDs)
    }

    // MARK: - Foreground Restoration

    /// フォアグラウンド復帰時: 通知センターとバッジをクリア（notifiedIDs は保持）
    func cancelAllAndResetBadge() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
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

    /// フォアグラウンド中は通知バナーを抑制（アプリ内カードで表示するため）
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
            completionHandler(); return  // 通知本体タップ → アプリを前面に出すだけ
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
