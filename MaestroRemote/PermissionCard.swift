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
                } else if let suggestion = perm.aiSuggestion, !suggestion.isEmpty {
                    aiSuggestionBadge(suggestion)
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

            // AI reason (if any)
            if let reason = perm.aiReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
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

    @ViewBuilder
    private func aiSuggestionBadge(_ suggestion: String) -> some View {
        let allow = suggestion == "yes"
        HStack(spacing: 3) {
            Image(systemName: "cpu")
                .font(.caption2)
            Text(allow ? "AI: Allow" : "AI: Deny")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(allow ? Color.green : Color.red)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill((allow ? Color.green : Color.red).opacity(0.1))
                .overlay(Capsule().strokeBorder((allow ? Color.green : Color.red).opacity(0.3), lineWidth: 0.5))
        )
    }
}
