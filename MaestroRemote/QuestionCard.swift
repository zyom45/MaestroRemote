import SwiftUI

struct QuestionCard: View {
    let question: MaestroClient.Question
    @EnvironmentObject var client: MaestroClient

    @State private var answerText = ""
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
                Text(question.projectName)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text("Question")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            // ── Message card ──────────────────────────────
            Text(question.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // ── Response area ─────────────────────────────
            if responded {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Responded").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if question.requiresTerminalInput {
                HStack(spacing: 6) {
                    Image(systemName: "terminal").font(.caption).foregroundStyle(.secondary)
                    Text("Answer required in terminal").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    if let items = parseNumberedItems(question.message) {
                        VStack(spacing: 6) {
                            ForEach(items, id: \.number) { item in
                                Button(action: { submit(item.text) }) {
                                    HStack(spacing: 8) {
                                        Text("\(item.number)")
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Circle().fill(Color.blue))
                                        Text(item.text)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray5))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Divider()
                    }
                    HStack(spacing: 8) {
                        TextField("Type freely...", text: $answerText)
                            .textFieldStyle(.roundedBorder)
                        Button("Send") { submit(answerText) }
                            .buttonStyle(.borderedProminent)
                            .disabled(answerText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .disabled(isResponding)
            }
        }
        .padding(.vertical, 8)
        .opacity(isResponding ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isResponding)
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            isResponding = true
            responded = await client.respondToQuestion(id: question.id, text: trimmed)
            if !responded { isResponding = false }
        }
    }

    // MARK: - Numbered Items Parser

    private struct NumberedItem { let number: Int; let text: String }

    private func parseNumberedItems(_ message: String) -> [NumberedItem]? {
        let lines = message.components(separatedBy: "\n")
        var items: [NumberedItem] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^(\d+)[.):\s]\s*(.*)"#, options: .regularExpression) != nil,
                  let numEnd = trimmed.firstIndex(where: { !$0.isNumber }),
                  let num = Int(String(trimmed[..<numEnd]))
            else { continue }
            let afterNum = String(trimmed[numEnd...])
                .trimmingCharacters(in: .init(charactersIn: ".) :\t"))
            items.append(NumberedItem(number: num, text: afterNum))
        }
        return items.count >= 2 ? items : nil
    }
}
