import SwiftUI

// MARK: - Public View

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .prose(let s):
            ProseView(text: s)
        case .code(let lang, let code):
            CodeBlockView(language: lang, code: code)
        case .table(let headers, let rows):
            MDTableView(headers: headers, rows: rows)
        case .heading(let level, let text):
            HeadingView(level: level, text: text)
        case .rule:
            Divider()
                .padding(.vertical, 2)
        }
    }
}

// MARK: - Heading

private struct HeadingView: View {
    let level: Int
    let text: String

    var body: some View {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .font(font)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(font)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var font: Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .subheadline.bold()
        }
    }
}

// MARK: - Prose (inline markdown via AttributedString)

private struct ProseView: View {
    let text: String

    var body: some View {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Code Block

private struct CodeBlockView: View {
    let language: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
    }
}

// MARK: - Table

private struct MDTableView: View {
    let headers: [String]
    let rows: [[String]]

    private var colCount: Int {
        max(headers.count, rows.map { $0.count }.max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ForEach(0..<colCount, id: \.self) { col in
                        cell(col < headers.count ? headers[col] : "", isHeader: true)
                        if col < colCount - 1 { dividerV }
                    }
                }
                .background(Color(.systemGray5))

                Divider()

                // Rows
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 0) {
                        ForEach(0..<colCount, id: \.self) { col in
                            cell(col < row.count ? row[col] : "", isHeader: false)
                            if col < colCount - 1 { dividerV }
                        }
                    }
                    .background(idx % 2 == 1 ? Color(.systemGray6) : Color.clear)
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        Group {
            if isHeader {
                Text(text)
                    .font(.system(.caption, design: .default).bold())
            } else if let attr = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attr)
                    .font(.system(.caption))
            } else {
                Text(text)
                    .font(.system(.caption))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 80, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var dividerV: some View {
        Color(.systemGray4).frame(width: 0.5)
    }
}

// MARK: - Parser

private enum MDBlock {
    case prose(String)
    case code(language: String, code: String)
    case table(headers: [String], rows: [[String]])
    case heading(level: Int, text: String)
    case rule
}

private func parseBlocks(_ text: String) -> [MDBlock] {
    var result: [MDBlock] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0
    var proseLines: [String] = []

    func flushProse() {
        let joined = proseLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty {
            result.append(contentsOf: splitProse(joined))
        }
        proseLines = []
    }

    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("```") {
            flushProse()
            let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var codeLines: [String] = []
            i += 1
            while i < lines.count && !lines[i].hasPrefix("```") {
                codeLines.append(lines[i])
                i += 1
            }
            result.append(.code(language: lang, code: codeLines.joined(separator: "\n")))
            i += 1   // skip closing ```
        } else {
            proseLines.append(line)
            i += 1
        }
    }
    flushProse()
    return result
}

/// Split prose text into headings, horizontal rules, tables, and plain prose
private func splitProse(_ text: String) -> [MDBlock] {
    var result: [MDBlock] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0
    var proseLines: [String] = []

    func flushProse() {
        let s = proseLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { result.append(.prose(s)) }
        proseLines = []
    }

    while i < lines.count {
        let line = lines[i]

        // Heading: line starts with one or more '#'
        if let (level, headingText) = parseHeading(line) {
            flushProse()
            result.append(.heading(level: level, text: headingText))
            i += 1

        // Horizontal rule: line is only '-', '*', or '_' (3+)
        } else if isHorizontalRule(line) {
            flushProse()
            result.append(.rule)
            i += 1

        // Table: pipe line followed by separator line
        } else if looksLikeTableRow(line)
                    && i + 1 < lines.count
                    && isSeparator(lines[i + 1]) {
            flushProse()
            let headers = parseCells(line)
            i += 2   // skip header + separator
            var rows: [[String]] = []
            while i < lines.count && looksLikeTableRow(lines[i]) {
                rows.append(parseCells(lines[i]))
                i += 1
            }
            result.append(.table(headers: headers, rows: rows))

        } else {
            proseLines.append(line)
            i += 1
        }
    }
    flushProse()
    return result
}

private func parseHeading(_ line: String) -> (level: Int, text: String)? {
    guard line.hasPrefix("#") else { return nil }
    var level = 0
    var rest = line[line.startIndex...]
    while rest.first == "#" {
        level += 1
        rest = rest.dropFirst()
    }
    guard level <= 6, rest.first == " " || rest.isEmpty else { return nil }
    let text = String(rest).trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : (level, text)
}

private func isHorizontalRule(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 3 else { return false }
    let nonSpace = trimmed.filter { !$0.isWhitespace }
    guard !nonSpace.isEmpty else { return false }
    let ch = nonSpace.first!
    return (ch == "-" || ch == "*" || ch == "_") && nonSpace.allSatisfy { $0 == ch }
}

private func looksLikeTableRow(_ line: String) -> Bool {
    line.contains("|")
}

private func isSeparator(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return false }
    return trimmed.allSatisfy { "|-: \t".contains($0) }
}

private func parseCells(_ line: String) -> [String] {
    var s = line.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("|") { s = String(s.dropFirst()) }
    if s.hasSuffix("|") { s = String(s.dropLast()) }
    return s.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
}
