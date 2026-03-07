import SwiftUI

struct PermissionCard: View {
    let perm: MaestroClient.Permission
    @EnvironmentObject var client: MaestroClient

    @State private var isResponding = false
    @State private var responded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: tool name + project
            HStack(alignment: .top, spacing: 10) {
                Text(perm.toolEmoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(perm.toolName)
                        .font(.headline)
                    Text(perm.projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if responded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }

            // Command / primary argument
            if !perm.primaryArg.isEmpty {
                Text(perm.primaryArg)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .lineLimit(5)
            }

            // Action buttons
            if !responded {
                HStack(spacing: 8) {
                    actionButton("No", action: "no", color: .red, icon: "xmark")
                    actionButton("Yes", action: "yes", color: .blue, icon: "checkmark")
                    actionButton("Always", action: "always_yes", color: .orange, icon: "bolt")
                }
                .disabled(isResponding)
            }
        }
        .padding(.vertical, 6)
        .opacity(isResponding ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isResponding)
    }

    @ViewBuilder
    private func actionButton(_ title: String, action: String, color: Color, icon: String) -> some View {
        Button {
            Task {
                isResponding = true
                responded = await client.respond(id: perm.id, action: action)
                if !responded { isResponding = false }
            }
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }

}
