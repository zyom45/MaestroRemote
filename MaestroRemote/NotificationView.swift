import SwiftUI

struct NotificationView: View {
    @EnvironmentObject var client: MaestroClient
    @State private var showSetup = false

    private var hasPending: Bool {
        !client.pendingPermissions.isEmpty || !client.pendingQuestions.isEmpty
    }

    var body: some View {
        Group {
            if !client.isConnected {
                disconnectedView
            } else if !hasPending {
                idleView
            } else {
                pendingList
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSetup = true } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupView(client: client)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Waiting for permissions...")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Claude Code approvals will appear here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if client.alwaysYes {
                Label("Always Yes is ON", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                    .padding(.top, 8)
            }
            if client.autoPilot {
                Label("AutoPilot is ON", systemImage: "cpu")
                    .foregroundStyle(.purple)
                    .font(.callout)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text("Cannot Connect")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Make sure Maestro is running on your Mac and both devices are on the same Wi-Fi.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let err = client.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Retry") { Task { await client.fetchPending() } }
                    .buttonStyle(.bordered)
                Button("Settings") { showSetup = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pending List (permissions + questions)

    private var pendingList: some View {
        List {
            if !client.pendingQuestions.isEmpty {
                Section("Questions") {
                    ForEach(client.pendingQuestions) { q in
                        QuestionCard(question: q)
                            .environmentObject(client)
                    }
                }
            }
            if !client.pendingPermissions.isEmpty {
                Section("Permissions") {
                    ForEach(client.pendingPermissions) { perm in
                        PermissionCard(perm: perm)
                            .environmentObject(client)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await client.fetchPending() }
    }
}
