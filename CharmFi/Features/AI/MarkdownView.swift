import SwiftUI

/// A small block-level Markdown renderer. `AttributedString(markdown:)` covers inline styling
/// (bold/italic/code) but not block structure, so this splits the source into blocks first —
/// headings, lists, fenced code, blockquotes, rules and GitHub pipe tables — and lets
/// `AttributedString` handle only the inline text within each block. The system prompt asks the
/// model for `| Category | Amount |`-style tables, so table rendering is the one block type worth
/// real layout (a bordered grid) rather than plain text.
struct MarkdownView: View {
    let text: String

    private enum Block {
        case heading(level: Int, text: String)
        case bulletItem(String)
        case numberedItem(String)
        case code(String)
        case quote(String)
        case rule
        case table(header: [String], rows: [[String]])
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let t):
            inline(t).font(level <= 1 ? .title3.bold() : (level == 2 ? .headline : .subheadline.bold()))
        case .bulletItem(let t):
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(t)
            }
        case .numberedItem(let t):
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(t)
            }
        case .code(let t):
            Text(t).font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
        case .quote(let t):
            HStack(spacing: 8) {
                Rectangle().fill(.secondary).frame(width: 3)
                inline(t).foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        case .table(let header, let rows):
            TableBlock(header: header, rows: rows)
        case .paragraph(let t):
            inline(t)
        }
    }

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }

    private static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphBuffer: [String] = []
        var codeBuffer: [String]? = nil

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            blocks.append(.paragraph(paragraphBuffer.joined(separator: " ")))
            paragraphBuffer = []
        }

        let lines = source.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let buffer = codeBuffer {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(buffer.joined(separator: "\n")))
                    codeBuffer = nil
                } else {
                    codeBuffer = buffer + [line]
                }
                i += 1
                continue
            }
            if trimmed.hasPrefix("```") {
                flushParagraph()
                codeBuffer = []
                i += 1
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }
            if trimmed.hasPrefix("#") {
                flushParagraph()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                blocks.append(.heading(level: level, text: String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
                i += 1
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bulletItem(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }
            if let dot = trimmed.range(of: ". "), trimmed[trimmed.startIndex..<dot.lowerBound].allSatisfy(\.isNumber) {
                flushParagraph()
                blocks.append(.numberedItem(String(trimmed[dot.upperBound...])))
                i += 1
                continue
            }
            // GFM pipe table: a header row, a "---|---" separator, then data rows.
            if trimmed.hasPrefix("|"), i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).range(of: "^\\|?[\\s:|-]+\\|?$", options: .regularExpression) != nil {
                flushParagraph()
                let header = splitRow(trimmed)
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(splitRow(lines[j].trimmingCharacters(in: .whitespaces)))
                    j += 1
                }
                blocks.append(.table(header: header, rows: rows))
                i = j
                continue
            }

            paragraphBuffer.append(trimmed)
            i += 1
        }
        flushParagraph()
        if let buffer = codeBuffer, !buffer.isEmpty { blocks.append(.code(buffer.joined(separator: "\n"))) }
        return blocks
    }

    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(.caption.bold())
                    }
                }
                Divider().gridCellColumns(header.count)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.caption)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
