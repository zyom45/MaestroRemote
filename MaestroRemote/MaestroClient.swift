import Foundation
import Combine
import UIKit

@MainActor
class MaestroClient: ObservableObject {
    @Published var pendingPermissions: [Permission] = []
    @Published var isConnected = false
    @Published var alwaysYes = false
    @Published var autoPilot = false
    @Published var errorMessage: String?

    @Published var baseURL: String = UserDefaults.standard.string(forKey: "maestro.baseURL") ?? "" {
        didSet { UserDefaults.standard.set(baseURL, forKey: "maestro.baseURL") }
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

            // 接続確立時: 保存済み APNs トークンを Mac へ送信
            if !wasConnected {
                let url = baseURL
                Task { await NotificationManager.shared.sendStoredTokenIfNeeded(baseURL: url) }
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

    private struct PendingResponse: Codable {
        let pending: [Permission]
        let alwaysYes: Bool
        let autoPilot: Bool
    }
}
