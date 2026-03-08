import SwiftUI

struct ContentView: View {
    @StateObject private var client = MaestroClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if client.baseURL.isEmpty {
                SetupView(client: client)
            } else {
                HomeView()
                    .environmentObject(client)
            }
        }
        .onAppear {
            client.startPolling()
            NotificationManager.shared.client = client
        }
        .onDisappear { client.stopPolling() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                NotificationManager.shared.isInBackground = true
                client.startBackgroundTask()
                let permissions = client.pendingPermissions
                let baseURL = client.baseURL
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run {
                        NotificationManager.shared.notifyAllPending(permissions, baseURL: baseURL)
                    }
                }
            case .active:
                NotificationManager.shared.isInBackground = false
                client.endBackgroundTask()
                NotificationManager.shared.cancelAllAndResetBadge()
            default:
                break
            }
        }
    }
}
