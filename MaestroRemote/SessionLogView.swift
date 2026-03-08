import SwiftUI

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
                    HStack {
                        if let tc = session.turnCount {
                            Text("\(tc) turns")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatTimestamp(session.modifiedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Session Turns

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
                    VStack(alignment: .leading, spacing: 8) {
                        if !turn.userMessage.isEmpty {
                            Text(turn.userMessage)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                                .lineLimit(3)
                        }
                        if !turn.assistantText.isEmpty {
                            Text(turn.assistantText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                        Text(formatTimestamp(turn.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
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
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
