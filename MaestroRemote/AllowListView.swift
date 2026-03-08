import SwiftUI

struct AllowListView: View {
    @EnvironmentObject var client: MaestroClient
    @State private var rules: MaestroClient.RulesPayload?
    @State private var isLoading = false
    @State private var unavailable = false
    @State private var showAddSheet = false
    @State private var newTool = ""

    private let knownTools = ["Bash", "Edit", "Write", "Read", "Glob", "Grep",
                               "WebFetch", "WebSearch", "Task", "NotebookEdit"]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if unavailable {
                unavailableView
            } else {
                list
            }
        }
        .navigationTitle("Allow List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .disabled(unavailable)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var list: some View {
        List {
            // グローバル allow list
            Section {
                if rules?.allowedTools.isEmpty ?? true {
                    Text("No tools in allow list")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules?.allowedTools ?? [], id: \.self) { tool in
                        HStack {
                            Text(toolEmoji(tool))
                            Text(tool)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                    }
                    .onDelete { indexSet in
                        let list = rules?.allowedTools ?? []
                        for i in indexSet {
                            Task { await removeTool(list[i]) }
                        }
                    }
                }
            } header: {
                Text("Global")
            } footer: {
                Text("Applied to all projects unless overridden.")
            }

            // プロジェクト別 allow list（設定があるもののみ表示）
            ForEach(rules?.registeredProjects.filter { $0.allowedTools != nil } ?? []) { project in
                Section {
                    ForEach(project.allowedTools ?? [], id: \.self) { tool in
                        HStack {
                            Text(toolEmoji(tool))
                            Text(tool)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                    }
                } header: {
                    Text(project.displayName)
                } footer: {
                    Text("Overrides global list for this project.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Select tool") {
                    ForEach(knownTools, id: \.self) { tool in
                        Button {
                            Task {
                                await addTool(tool)
                                showAddSheet = false
                            }
                        } label: {
                            HStack {
                                Text(toolEmoji(tool))
                                Text(tool)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if rules?.allowedTools.contains(tool) == true {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                    }
                }
                Section("Custom tool name") {
                    HStack {
                        TextField("ToolName", text: $newTool)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                        Button("Add") {
                            guard !newTool.isEmpty else { return }
                            let t = newTool
                            newTool = ""
                            Task {
                                await addTool(t)
                                showAddSheet = false
                            }
                        }
                        .disabled(newTool.isEmpty)
                    }
                }
            }
            .navigationTitle("Add Tool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showAddSheet = false }
                }
            }
        }
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
        let result = await client.fetchRules()
        if result == nil && !client.baseURL.isEmpty {
            unavailable = true
        }
        rules = result
        isLoading = false
    }

    private func addTool(_ tool: String) async {
        let ok = await client.addAllow(tool: tool)
        if ok { await load() }
    }

    private func removeTool(_ tool: String) async {
        let ok = await client.removeAllow(tool: tool)
        if ok { await load() }
    }

    private func toolEmoji(_ name: String) -> String {
        switch name {
        case "Bash":                    return "⌨️"
        case "Edit":                    return "✏️"
        case "Write":                   return "📝"
        case "Read":                    return "📖"
        case "WebFetch", "WebSearch":   return "🌐"
        case "Glob":                    return "🔍"
        case "Grep":                    return "🎯"
        default:                        return "⚙️"
        }
    }
}
