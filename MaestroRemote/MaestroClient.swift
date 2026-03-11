import Foundation
import Combine
import UIKit

@MainActor
class MaestroClient: ObservableObject {
    @Published var pendingPermissions: [Permission] = []
    @Published var pendingQuestions: [Question] = []
    @Published var isConnected = false
    @Published var alwaysYes = false
    @Published var autoPilot = false
    @Published var errorMessage: String?

    @Published var baseURL: String = UserDefaults.standard.string(forKey: "maestro.baseURL") ?? "" {
        didSet { UserDefaults.standard.set(baseURL, forKey: "maestro.baseURL") }
    }

    @Published var notificationsEnabled: Bool =
        UserDefaults.standard.object(forKey: "maestro.notificationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "maestro.notificationsEnabled") }
    }

    /// テストで差し替え可能な URLSession
    static var urlSession: URLSession = .shared
    private var session: URLSession { MaestroClient.urlSession }

    private var pollTask: Task<Void, Never>?
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        guard !baseURL.isEmpty else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await fetchPending()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func fetchPending() async {
        guard !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/pending") else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                isConnected = false; return
            }
            let decoded = try JSONDecoder().decode(PendingResponse.self, from: data)
            pendingPermissions = decoded.pending
            pendingQuestions = decoded.questions ?? []
            alwaysYes = decoded.alwaysYes
            autoPilot = decoded.autoPilot
            let wasConnected = isConnected
            isConnected = true
            errorMessage = nil

            let activeIDs = Set(decoded.pending.map { $0.id })
            NotificationManager.shared.cleanupResolvedIDs(activeIDs)

            // バックグラウンド中のみ: 未通知の新着 permission を即時通知
            if NotificationManager.shared.isInBackground {
                for perm in decoded.pending {
                    NotificationManager.shared.notify(for: perm, baseURL: baseURL)
                }
            }

            // 接続確立時: 保存済み APNs トークンと通知設定を Mac へ送信
            if !wasConnected {
                let url = baseURL
                let enabled = notificationsEnabled
                Task {
                    await NotificationManager.shared.sendStoredTokenIfNeeded(baseURL: url)
                    if !enabled, let token = NotificationManager.shared.deviceToken {
                        await self.syncNotificationConfig(token: token, enabled: false, baseURL: url)
                    }
                }
            }
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }

    func respond(id: UUID, action: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/respond") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "id": id.uuidString,
            "action": action
        ])
        do {
            let (data, _) = try await session.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["ok"] as? Bool == true || json["status"] as? String == "ok" {
                pendingPermissions.removeAll { $0.id == id }
                NotificationManager.shared.cancelNotification(for: id)
                return true
            }
        } catch {}
        return false
    }

    func respondToQuestion(id: UUID, text: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/respond-question") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id.uuidString, "text": text])
        do {
            let (data, _) = try await session.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["ok"] as? Bool == true {
                pendingQuestions.removeAll { $0.id == id }
                return true
            }
        } catch {}
        return false
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        notificationsEnabled = enabled
        guard !baseURL.isEmpty, let token = NotificationManager.shared.deviceToken, !token.isEmpty else { return }
        await syncNotificationConfig(token: token, enabled: enabled, baseURL: baseURL)
    }

    private func syncNotificationConfig(token: String, enabled: Bool, baseURL: String) async {
        guard let url = URL(string: "\(baseURL)/api/notifications/config") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceToken": token,
            "notificationsEnabled": enabled
        ])
        _ = try? await session.data(for: req)
    }

    func setBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = trimmed
        isConnected = false
        errorMessage = nil
        startPolling()
    }

    // MARK: - Background Task

    /// バックグラウンド移行時に呼ぶ。約30秒間ポーリングを継続できる。
    func startBackgroundTask() {
        guard bgTaskID == .invalid else { return }
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "MaestroPolling") {
            // タイムアウト直前: 残っている pending を通知してから終了
            MainActor.assumeIsolated {
                NotificationManager.shared.notifyAllPending(
                    self.pendingPermissions,
                    baseURL: self.baseURL
                )
                self.endBackgroundTask()
            }
        }
    }

    func endBackgroundTask() {
        guard bgTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTaskID)
        bgTaskID = .invalid
    }

    // MARK: - Models

    struct Permission: Identifiable, Codable {
        let id: UUID
        let toolName: String
        let toolInput: String   // JSON string
        let label: String
        let cwd: String
        let sessionId: String
        let enqueuedAt: String

        var toolEmoji: String {
            switch toolName {
            case "Bash":                        return "⌨️"
            case "Edit":                        return "✏️"
            case "Write":                       return "📝"
            case "Read":                        return "📖"
            case "WebFetch", "WebSearch":       return "🌐"
            case "Glob":                        return "🔍"
            case "Grep":                        return "🔎"
            default:                            return "⚙️"
            }
        }

        var primaryArg: String {
            guard let data = toolInput.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return "" }
            return obj["command"] as? String
                ?? obj["file_path"] as? String
                ?? obj["query"] as? String
                ?? obj["url"] as? String
                ?? ""
        }

        var projectName: String {
            guard !cwd.isEmpty else { return label }
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
    }

    struct Question: Identifiable, Codable {
        let id: UUID
        let message: String
        let label: String
        let cwd: String
        let sessionId: String
        let requiresTerminalInput: Bool
        let enqueuedAt: String

        var projectName: String {
            guard !cwd.isEmpty else { return label }
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
    }

    private struct PendingResponse: Codable {
        let pending: [Permission]
        let questions: [Question]?
        let alwaysYes: Bool
        let autoPilot: Bool
    }

    // MARK: - Dashboard Models

    struct HistoryRecord: Identifiable, Codable {
        let id: Int64
        let timestamp: String
        let project: String
        let cwd: String
        let toolName: String
        let toolInput: String
        let action: String
        let duration: Double

        var actionEmoji: String {
            switch action {
            case "yes":        return "✅"
            case "no":         return "❌"
            case "always_yes": return "⚡"
            default:           return "💬"
            }
        }
    }

    struct ActivityRecord: Identifiable, Codable {
        let id: Int64
        let sessionId: String
        let timestamp: String
        let project: String
        let cwd: String
        let toolName: String
        let toolInput: String
    }

    struct SessionSummary: Identifiable, Codable {
        let id: String
        let projectName: String
        let projectDir: String
        let modifiedAt: String
        let turnCount: Int?
    }

    struct TurnItem: Codable {
        let type: String       // "text" | "fileOp"
        let content: String?   // text only
        let kind: String?      // fileOp only
        let path: String?      // fileOp only
    }

    struct TurnSummary: Identifiable, Codable {
        let id: String
        let userMessage: String
        let timestamp: String
        let items: [TurnItem]

        var assistantText: String {
            items.compactMap { $0.type == "text" ? $0.content : nil }.joined(separator: "\n")
        }
    }

    struct RulesPayload: Codable {
        let allowedTools: [String]
        let blockRules: [BlockRule]
        let registeredProjects: [RegisteredProject]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            allowedTools        = try c.decodeIfPresent([String].self,             forKey: .allowedTools)        ?? []
            blockRules          = try c.decodeIfPresent([BlockRule].self,          forKey: .blockRules)          ?? []
            registeredProjects  = try c.decodeIfPresent([RegisteredProject].self,  forKey: .registeredProjects)  ?? []
        }

        struct BlockRule: Identifiable, Codable {
            let id: String
            let toolName: String
            let pattern: String
            let note: String
        }

        struct RegisteredProject: Identifiable, Codable {
            let id: String
            let displayName: String
            let allowedTools: [String]?   // nil = グローバルにフォールバック
            let blockRules: [BlockRule]?  // nil = グローバルにフォールバック
        }
    }
}

// MARK: - Dashboard API

extension MaestroClient {

    /// Mac API は {"data": [...]} ラッパーで返す
    private struct DataWrapper<T: Decodable>: Decodable {
        let data: [T]
    }

    /// HTTP 200 → (data, false)、404/エラー → ([], true)
    private func fetchDataArray<T: Decodable>(_ urlString: String) async -> (items: [T], unavailable: Bool) {
        guard let url = URL(string: urlString) else { return ([], true) }
        guard let (data, resp) = try? await session.data(from: url) else { return ([], true) }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return ([], true) }
        let items = (try? JSONDecoder().decode(DataWrapper<T>.self, from: data))?.data ?? []
        return (items, false)
    }

    func fetchHistory(limit: Int = 100) async -> (items: [HistoryRecord], unavailable: Bool) {
        await fetchDataArray("\(baseURL)/api/history?limit=\(limit)")
    }

    func fetchActivity(limit: Int = 200) async -> (items: [ActivityRecord], unavailable: Bool) {
        await fetchDataArray("\(baseURL)/api/activity?limit=\(limit)")
    }

    func fetchSessions() async -> (items: [SessionSummary], unavailable: Bool) {
        await fetchDataArray("\(baseURL)/api/sessions")
    }

    func fetchTurns(sessionId: String, limit: Int = 50, offset: Int = 0) async -> [TurnSummary] {
        guard let url = URL(string: "\(baseURL)/api/sessions/\(sessionId)/turns?limit=\(limit)&offset=\(offset)") else { return [] }
        guard let (data, _) = try? await session.data(from: url) else { return [] }
        return (try? JSONDecoder().decode(DataWrapper<TurnSummary>.self, from: data))?.data ?? []
    }

    func fetchRules() async -> RulesPayload? {
        guard let url = URL(string: "\(baseURL)/api/rules") else { return nil }
        guard let (data, resp) = try? await session.data(from: url) else { return nil }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(RulesPayload.self, from: data)
    }

    @discardableResult
    func addAllow(tool: String) async -> Bool {
        await postJSON(path: "/api/allow-list/add", body: ["tool": tool])
    }

    @discardableResult
    func removeAllow(tool: String) async -> Bool {
        await postJSON(path: "/api/allow-list/remove", body: ["tool": tool])
    }

    @discardableResult
    func addBlockRule(toolName: String, pattern: String, note: String) async -> Bool {
        await postJSON(path: "/api/block-list/add",
                       body: ["toolName": toolName, "pattern": pattern, "note": note])
    }

    @discardableResult
    func removeBlockRule(id: String) async -> Bool {
        await postJSON(path: "/api/block-list/remove", body: ["id": id])
    }

    private func postJSON(path: String, body: [String: String]) async -> Bool {
        guard let url = URL(string: "\(baseURL)\(path)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["status"] as? String == "ok" || json["ok"] as? Bool == true
    }
}
