import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var client: MaestroClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Rules") {
                NavigationLink {
                    AllowListView().environmentObject(client)
                } label: {
                    Label("Allow List", systemImage: "checkmark.shield.fill")
                }
                NavigationLink {
                    BlockListView().environmentObject(client)
                } label: {
                    Label("Block List", systemImage: "xmark.shield.fill")
                }
            }

            Section("Logs") {
                NavigationLink {
                    ActivityView().environmentObject(client)
                } label: {
                    Label("Activity", systemImage: "bolt.fill")
                }
                NavigationLink {
                    HistoryView().environmentObject(client)
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { client.notificationsEnabled },
                    set: { enabled in Task { await client.setNotificationsEnabled(enabled) } }
                )) {
                    Label("Push Notifications", systemImage: "bell.fill")
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("When off, Maestro will not send push notifications to this device.")
            }

            Section("Connection") {
                HStack {
                    Label("Status", systemImage: "circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(client.isConnected ? Color.green : Color.red, Color.clear)
                    Spacer()
                    Text(client.isConnected ? "Connected" : "Disconnected")
                        .foregroundStyle(.secondary)
                }
                if !client.baseURL.isEmpty {
                    HStack {
                        Text("Server")
                        Spacer()
                        Text(client.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                NavigationLink {
                    SetupView(client: client)
                } label: {
                    Label("Configure", systemImage: "gear")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
