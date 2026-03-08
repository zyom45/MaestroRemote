import SwiftUI

struct HomeView: View {
    @EnvironmentObject var client: MaestroClient
    @State private var showSetup = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    NavigationLink {
                        NotificationView().environmentObject(client)
                    } label: {
                        FeatureCard(
                            title: "Notifications",
                            icon: "bell.badge.fill",
                            color: .orange,
                            badge: client.pendingPermissions.count
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SessionLogView().environmentObject(client)
                    } label: {
                        FeatureCard(title: "Session Log",
                                    icon: "bubble.left.and.bubble.right.fill",
                                    color: .blue)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ActivityView().environmentObject(client)
                    } label: {
                        FeatureCard(title: "Activity",
                                    icon: "bolt.fill",
                                    color: .green)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        HistoryView().environmentObject(client)
                    } label: {
                        FeatureCard(title: "History",
                                    icon: "clock.arrow.circlepath",
                                    color: .purple)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AllowListView().environmentObject(client)
                    } label: {
                        FeatureCard(title: "Allow List",
                                    icon: "checkmark.shield.fill",
                                    color: .teal)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        BlockListView().environmentObject(client)
                    } label: {
                        FeatureCard(title: "Block List",
                                    icon: "xmark.shield.fill",
                                    color: .red)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("Maestro")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { connectionBadge }
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
    }

    private var connectionBadge: some View {
        Circle()
            .fill(client.isConnected ? Color.green : Color.red)
            .frame(width: 10, height: 10)
    }
}

// MARK: - Feature Card

struct FeatureCard: View {
    let title: String
    let icon: String
    let color: Color
    var badge: Int = 0

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
                    .frame(width: 52, height: 52)

                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .offset(x: 14, y: -4)
                }
            }

            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
