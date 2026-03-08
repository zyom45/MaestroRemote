import SwiftUI

struct BlockListView: View {
    @EnvironmentObject var client: MaestroClient
    @State private var rules: MaestroClient.RulesPayload?
    @State private var isLoading = false
    @State private var unavailable = false
    @State private var showAddSheet = false
    @State private var newToolName = ""
    @State private var newPattern = ""
    @State private var newNote = ""

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
        .navigationTitle("Block List")
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
            Section {
                if rules?.blockRules.isEmpty ?? true {
                    Text("No block rules")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules?.blockRules ?? []) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rule.toolName == "*" ? "All tools" : rule.toolName)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            if !rule.pattern.isEmpty {
                                Text("Pattern: \(rule.pattern)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !rule.note.isEmpty {
                                Text(rule.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { indexSet in
                        let ruleList = rules?.blockRules ?? []
                        for i in indexSet {
                            Task { await removeRule(ruleList[i].id) }
                        }
                    }
                }
            } header: {
                Text("Block rules")
            } footer: {
                Text("Matching tool calls are automatically denied.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Tool") {
                    TextField("Bash, Edit, * (all tools)", text: $newToolName)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                Section {
                    TextField("e.g. rm -rf  (empty = block entire tool)", text: $newPattern)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                } header: {
                    Text("Pattern (optional)")
                } footer: {
                    Text("Blocks calls where the tool input contains this string.")
                }
                Section("Note") {
                    TextField("Why this is blocked", text: $newNote)
                }
                Section {
                    Button("Add Rule") {
                        guard !newToolName.isEmpty else { return }
                        let t = newToolName; let p = newPattern; let n = newNote
                        newToolName = ""; newPattern = ""; newNote = ""
                        Task {
                            await addRule(toolName: t, pattern: p, note: n)
                            showAddSheet = false
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(newToolName.isEmpty)
                }
            }
            .navigationTitle("Add Block Rule")
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

    private func addRule(toolName: String, pattern: String, note: String) async {
        let ok = await client.addBlockRule(toolName: toolName, pattern: pattern, note: note)
        if ok { await load() }
    }

    private func removeRule(_ id: String) async {
        let ok = await client.removeBlockRule(id: id)
        if ok { await load() }
    }
}
