import SwiftUI

struct PermissionCard: View {
    let perm: MaestroClient.Permission
    @EnvironmentObject var client: MaestroClient

    @State private var isResponding = false
    @State private var responded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Project name ──────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(perm.projectName)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            // ── Tool card ─────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: toolIconName(perm.toolName))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                    Text(perm.toolName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                }

                if !perm.primaryArg.isEmpty {
                    Text(perm.primaryArg)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(8)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // ── Action buttons ────────────────────────────
            if responded {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Responded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        noButton
                        yesButton
                    }
                    dontAskAgainButton
                }
                .disabled(isResponding)
            }
        }
        .padding(.vertical, 8)
        .opacity(isResponding ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isResponding)
    }

    // MARK: - Buttons

    private var noButton: some View {
        Button { respond(action: "no") } label: {
            Text("No").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private var yesButton: some View {
        Button { respond(action: "yes") } label: {
            Text("Yes").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    private var dontAskAgainButton: some View {
        Button { respond(action: "dont_ask_again") } label: {
            Text("Don't Ask Again").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .controlSize(.small)
    }

    private func respond(action: String) {
        Task {
            isResponding = true
            responded = await client.respond(id: perm.id, action: action)
            if !responded { isResponding = false }
        }
    }

    // MARK: - Tool Icon

    private func toolIconName(_ name: String) -> String {
        switch name {
        case "Bash":                  return "terminal"
        case "Edit":                  return "pencil"
        case "Write":                 return "doc.badge.plus"
        case "Read":                  return "doc.text"
        case "WebFetch", "WebSearch": return "globe"
        case "Glob":                  return "magnifyingglass"
        case "Grep":                  return "text.magnifyingglass"
        default:                      return "gear"
        }
    }
}
