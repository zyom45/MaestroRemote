import SwiftUI

// MARK: - Session List

struct SessionLogView: View {
    @EnvironmentObject var client: MaestroClient
    @State private var sessions: [MaestroClient.SessionSummary] = []
    @State private var isLoading = false
    @State private var unavailable = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if unavailable {
                unavailableView
            } else if sessions.isEmpty {
                emptyView
            } else {
                list
            }
        }
        .navigationTitle("Session Log")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var list: some View {
        List(sessions) { session in
            NavigationLink {
                SessionTurnsView(session: session)
                    .environmentObject(client)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.projectName)
                        .font(.headline)
                    Text(session.projectDir)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTimestamp(session.modifiedAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No sessions yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Requires Maestro Update")
                .font(.headline)
            Text("Update Maestro on your Mac to enable this feature.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true
        unavailable = false
        let result = await client.fetchSessions()
        unavailable = result.unavailable
        sessions = result.items
        isLoading = false
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Turns List

struct SessionTurnsView: View {
    @EnvironmentObject var client: MaestroClient
    let session: MaestroClient.SessionSummary
    @State private var turns: [MaestroClient.TurnSummary] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if turns.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No turns")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(turns) { turn in
                    NavigationLink {
                        TurnDetailView(turn: turn)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if !turn.userMessage.isEmpty {
                                Text(turn.userMessage)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                            } else {
                                Text("(no message)")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(formatTimestamp(turn.timestamp))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(session.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        turns = await client.fetchTurns(sessionId: session.id)
        isLoading = false
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Turn Detail

struct TurnDetailView: View {
    let turn: MaestroClient.TurnSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // User message
                if !turn.userMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("User", systemImage: "person.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                        Text(turn.userMessage)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }

                // Assistant items
                ForEach(Array(turn.items.enumerated()), id: \.offset) { _, item in
                    switch item.type {
                    case "text":
                        if let text = item.content, !text.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Assistant", systemImage: "sparkles")
                                    .font(.caption.bold())
                                    .foregroundStyle(.purple)
                                Text(text)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }
                    case "fileOp":
                        if let path = item.path {
                            HStack(spacing: 8) {
                                Image(systemName: fileOpIcon(item.kind))
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 4)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .padding()
        }
        .navigationTitle(turn.userMessage.isEmpty ? "Turn" : String(turn.userMessage.prefix(40)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fileOpIcon(_ kind: String?) -> String {
        switch kind {
        case "edit":   return "pencil.and.outline"
        case "write":  return "plus.square"
        case "bashRm": return "trash"
        default:       return "doc"
        }
    }
}
