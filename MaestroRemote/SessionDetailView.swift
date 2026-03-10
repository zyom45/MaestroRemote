import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var client: MaestroClient
    let projectName: String
    let session: MaestroClient.SessionSummary?

    @State private var turns: [MaestroClient.TurnSummary] = []
    @State private var isLoadingTurns = false

    private var pendingPerms: [MaestroClient.Permission] {
        client.pendingPermissions.filter {
            URL(fileURLWithPath: $0.cwd).lastPathComponent == projectName
        }
    }

    private var pendingQuestions: [MaestroClient.Question] {
        client.pendingQuestions.filter {
            URL(fileURLWithPath: $0.cwd).lastPathComponent == projectName
        }
    }

    private var hasPending: Bool {
        !pendingPerms.isEmpty || !pendingQuestions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            chatArea
            if hasPending {
                Divider()
                pendingArea
            }
        }
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadTurns() }
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if isLoadingTurns {
                        ProgressView().padding(.top, 40)
                    } else if turns.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text(session == nil ? "No session history" : "No turns yet")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(turns) { turn in
                            TurnBubble(turn: turn)
                                .id(turn.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: turns.count) { _, _ in
                if let last = turns.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .task {
                await loadTurns()
                if let last = turns.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Pending Area (pinned bottom)

    private var pendingArea: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(pendingQuestions) { q in
                    QuestionCard(question: q)
                        .environmentObject(client)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                ForEach(pendingPerms) { perm in
                    PermissionCard(perm: perm)
                        .environmentObject(client)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                Spacer().frame(height: 16)
            }
        }
        .frame(maxHeight: 320)
        .background(Color(.systemBackground))
    }

    // MARK: - Load

    private func loadTurns() async {
        guard let session else { return }
        isLoadingTurns = true
        turns = await client.fetchTurns(sessionId: session.id)
        isLoadingTurns = false
    }
}

// MARK: - Turn Bubble

private struct TurnBubble: View {
    let turn: MaestroClient.TurnSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // User message
            if !turn.userMessage.isEmpty {
                HStack {
                    Spacer(minLength: 56)
                    Text(turn.userMessage)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)
                }
            }

            // Assistant text items
            let textItems = turn.items.filter { $0.type == "text" && ($0.content?.isEmpty == false) }
            if !textItems.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(textItems.enumerated()), id: \.offset) { _, item in
                            if let text = item.content {
                                MarkdownView(text: text)
                                    .font(.body)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        Color(.systemGray6),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    )
                            }
                        }
                    }
                    Spacer(minLength: 40)
                }
            }

            // File operations
            let fileOps = turn.items.filter { $0.type == "fileOp" && $0.path != nil }
            if !fileOps.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(fileOps.enumerated()), id: \.offset) { _, item in
                        if let path = item.path {
                            HStack(spacing: 5) {
                                Image(systemName: fileOpIcon(item.kind))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)
                                Text(path)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.leading, 24)
            }

            // Timestamp
            Text(formatTimestamp(turn.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
        }
    }

    private func fileOpIcon(_ kind: String?) -> String {
        switch kind {
        case "edit":   return "pencil.and.outline"
        case "write":  return "plus.square"
        case "bashRm": return "trash"
        default:       return "doc"
        }
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
