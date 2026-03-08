import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var client: MaestroClient
    @State private var records: [MaestroClient.HistoryRecord] = []
    @State private var isLoading = false
    @State private var unavailable = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if unavailable {
                unavailableView
            } else if records.isEmpty {
                emptyView
            } else {
                list
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var list: some View {
        List(records) { record in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record.actionEmoji + " " + record.toolName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    Spacer()
                    Text(formatTimestamp(record.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(record.project)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !primaryArg(record.toolInput).isEmpty {
                    Text(primaryArg(record.toolInput))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.insetGrouped)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No history yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Requires Maestro Update")
                .font(.headline)
            Text("Update Maestro on your Mac to enable this feature.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true
        unavailable = false
        let result = await client.fetchHistory()
        unavailable = result.unavailable
        records = result.items
        isLoading = false
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }

    private func primaryArg(_ toolInput: String) -> String {
        guard let data = toolInput.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }
        return obj["command"] as? String
            ?? obj["file_path"] as? String
            ?? obj["query"] as? String
            ?? obj["url"] as? String
            ?? ""
    }
}
