import Foundation
import Combine

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

    private var pollTask: Task<Void, Never>?

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
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                isConnected = false; return
            }
            let decoded = try JSONDecoder().decode(PendingResponse.self, from: data)
            pendingPermissions = decoded.pending
            alwaysYes = decoded.alwaysYes
            autoPilot = decoded.autoPilot
            isConnected = true
            errorMessage = nil
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
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["ok"] as? Bool == true || json["status"] as? String == "ok" {
                pendingPermissions.removeAll { $0.id == id }
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

    // MARK: - Models

    struct Permission: Identifiable, Codable {
        let id: UUID
        let toolName: String
        let toolInput: String   // JSON string
        let label: String
        let cwd: String
        let sessionId: String
        let enqueuedAt: String
        var aiSuggestion: String?
        var aiReason: String?

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
