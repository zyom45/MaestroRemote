import SwiftUI

struct ContentView: View {
    @StateObject private var client = MaestroClient()
    @State private var showSetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if client.baseURL.isEmpty {
                    SetupView(client: client)
                } else if !client.isConnected {
                    DisconnectedView(onOpenSettings: { showSetup = true })
                        .environmentObject(client)
                } else if client.pendingPermissions.isEmpty {
                    IdleView()
                        .environmentObject(client)
                } else {
                    PermissionListView()
                        .environmentObject(client)
                }
            }
            .navigationTitle("Maestro")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    connectionBadge
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSetup = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupView(client: client)
        }
        .onAppear {
            client.startPolling()
            NotificationManager.shared.client = client
        }
        .onDisappear { client.stopPolling() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // バックグラウンド移行時: pending 全件を通知として発火（バッジ含む）
                NotificationManager.shared.notifyAllPending(
                    client.pendingPermissions,
                    baseURL: client.baseURL
                )
            case .active:
                // フォアグラウンド復帰時: 通知センターとバッジをクリア
                NotificationManager.shared.cancelAllAndResetBadge()
            default:
                break
            }
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(client.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            if client.isConnected {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Idle State

struct IdleView: View {
    @EnvironmentObject var client: MaestroClient

    var body: some View {
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
}

// MARK: - Disconnected State

struct DisconnectedView: View {
    @EnvironmentObject var client: MaestroClient
    let onOpenSettings: () -> Void

    var body: some View {
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
                Button("Retry") {
                    Task { await client.fetchPending() }
                }
                .buttonStyle(.bordered)

                Button("Settings") { onOpenSettings() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Permission List

struct PermissionListView: View {
    @EnvironmentObject var client: MaestroClient

    var body: some View {
        List(client.pendingPermissions) { perm in
            PermissionCard(perm: perm)
                .environmentObject(client)
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await client.fetchPending()
        }
    }
}
