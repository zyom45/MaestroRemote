import SwiftUI

struct HomeView: View {
    @EnvironmentObject var client: MaestroClient
    @State private var sessions: [MaestroClient.SessionSummary] = []
    @State private var isLoading = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            sessionList
                .navigationTitle("Maestro")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Circle()
                            .fill(client.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView().environmentObject(client)
            }
        }
        .task { await load() }
    }

    // MARK: - Computed

    private func pendingPerms(for name: String) -> [MaestroClient.Permission] {
        client.pendingPermissions.filter {
            URL(fileURLWithPath: $0.cwd).lastPathComponent == name
        }
    }

    private func pendingQuestions(for name: String) -> [MaestroClient.Question] {
        client.pendingQuestions.filter {
            URL(fileURLWithPath: $0.cwd).lastPathComponent == name
        }
    }

    private func totalPending(for name: String) -> Int {
        pendingPerms(for: name).count + pendingQuestions(for: name).count
    }

    /// Project names from pending items that have no matching session
    private var orphanedProjectNames: [String] {
        let sessionNames = Set(sessions.map { $0.projectName })
        let all = (client.pendingPermissions.map { URL(fileURLWithPath: $0.cwd).lastPathComponent }
                 + client.pendingQuestions.map { URL(fileURLWithPath: $0.cwd).lastPathComponent })
        return Array(Set(all).subtracting(sessionNames)).sorted()
    }

    /// Sessions that have at least one pending item, sorted most-recent first
    private var activeSessions: [MaestroClient.SessionSummary] {
        sessions.filter { totalPending(for: $0.projectName) > 0 }
                .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Sessions with no pending items, sorted most-recent first
    private var recentSessions: [MaestroClient.SessionSummary] {
        sessions.filter { totalPending(for: $0.projectName) == 0 }
                .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func rowSubtitle(for name: String) -> String? {
        let questions = pendingQuestions(for: name)
        let perms = pendingPerms(for: name)
        if let q = questions.first {
            return "Question: \(q.message.prefix(60))"
        }
        if let p = perms.first {
            return "Waiting: \(p.toolName)"
        }
        return nil
    }

    // MARK: - Views

    private var sessionList: some View {
        List {
            // Active section: orphaned pending + sessions with pending
            if !orphanedProjectNames.isEmpty || !activeSessions.isEmpty {
                Section("Active") {
                    ForEach(orphanedProjectNames, id: \.self) { name in
                        NavigationLink {
                            SessionDetailView(projectName: name, session: nil)
                                .environmentObject(client)
                        } label: {
                            SessionRowLabel(
                                projectName: name,
                                subtitle: rowSubtitle(for: name) ?? "",
                                pendingCount: totalPending(for: name)
                            )
                        }
                    }
                    ForEach(activeSessions) { session in
                        NavigationLink {
                            SessionDetailView(projectName: session.projectName, session: session)
                                .environmentObject(client)
                        } label: {
                            SessionRowLabel(
                                projectName: session.projectName,
                                subtitle: rowSubtitle(for: session.projectName) ?? session.projectDir,
                                timestamp: session.modifiedAt,
                                pendingCount: totalPending(for: session.projectName)
                            )
                        }
                    }
                }
            }

            // Recent section: sessions without pending
            if !recentSessions.isEmpty {
                Section("Recent") {
                    ForEach(recentSessions) { session in
                        NavigationLink {
                            SessionDetailView(projectName: session.projectName, session: session)
                                .environmentObject(client)
                        } label: {
                            SessionRowLabel(
                                projectName: session.projectName,
                                subtitle: session.projectDir,
                                timestamp: session.modifiedAt
                            )
                        }
                    }
                }
            }

            // Empty state
            if sessions.isEmpty && orphanedProjectNames.isEmpty {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if !client.isConnected {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.red)
                        Text("Not Connected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Open Settings to configure the server address.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    Text("No sessions yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        let result = await client.fetchSessions()
        sessions = result.items
        isLoading = false
    }
}

// MARK: - Row Label

private struct SessionRowLabel: View {
    let projectName: String
    let subtitle: String
    var timestamp: String? = nil
    var pendingCount: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(projectName)
                    .font(.headline)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let ts = timestamp {
                    Text(formatTimestamp(ts))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.orange, in: Capsule())
            }
        }
        .padding(.vertical, 4)
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
