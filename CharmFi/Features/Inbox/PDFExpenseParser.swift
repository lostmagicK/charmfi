import PDFKit
import Foundation

enum PDFParseError: LocalizedError {
    case cannotOpen
    case passwordRequired
    case noTransactionsFound

    var errorDescription: String? {
        switch self {
        case .cannotOpen: "Could not open PDF file."
        case .passwordRequired: "PDF is password protected — enter the password and try again."
        case .noTransactionsFound: "No transactions found. Configure email patterns that match this bank's statement format."
        }
    }
}

struct PDFExpenseParser {
    func extractText(url: URL, password: String?) throws -> String {
        guard let document = PDFDocument(url: url) else { throw PDFParseError.cannotOpen }
        if document.isLocked {
            guard let pwd = password, !pwd.isEmpty, document.unlock(withPassword: pwd) else {
                throw PDFParseError.passwordRequired
            }
        }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) { text += extractTextByPosition(from: page) + "\n" }
        }
        return text
    }

    func parse(url: URL, password: String?, patterns: [EmailPattern]) throws -> [ParsedExpense] {
        guard let document = PDFDocument(url: url) else { throw PDFParseError.cannotOpen }
        if document.isLocked {
            guard let pwd = password, !pwd.isEmpty, document.unlock(withPassword: pwd) else {
                throw PDFParseError.passwordRequired
            }
        }

        var posText = ""
        var streamText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                posText += extractTextByPosition(from: page) + "\n"
                streamText += (page.string ?? "") + "\n"
            }
        }

        // Try tabular parser on position-based text first, then stream text
        if let results = parseTabular(from: posText), !results.isEmpty { return results }
        if let results = parseTabular(from: streamText), !results.isEmpty { return results }

        // Fall back to line-by-line on position text
        let lineResults = parseLineByLine(from: posText)
        if !lineResults.isEmpty { return lineResults }

        throw PDFParseError.noTransactionsFound
    }

    // MARK: - Position-aware extraction

    private func extractTextByPosition(from page: PDFPage) -> String {
        guard let raw = page.string, !raw.isEmpty else { return "" }
        // Index via NSString (UTF-16) so positions align with characterBounds(at:).
        let ns = raw as NSString
        let pageHeight = page.bounds(for: .mediaBox).height

        struct Glyph { let s: String; let minX: CGFloat; let maxX: CGFloat; let midY: CGFloat; let height: CGFloat }
        var glyphs: [Glyph] = []
        glyphs.reserveCapacity(ns.length)

        for i in 0..<ns.length {
            let s = ns.substring(with: NSRange(location: i, length: 1))
            if s == "\n" || s == "\r" { continue }   // lines are rebuilt from geometry
            let rect = page.characterBounds(at: i)
            guard !rect.isNull, rect.width.isFinite, rect.height > 0 else { continue }
            // PDF origin is bottom-left (Y up); flip so smaller value = higher on the page.
            glyphs.append(Glyph(s: s, minX: rect.minX, maxX: rect.maxX,
                                midY: pageHeight - rect.midY, height: rect.height))
        }
        guard !glyphs.isEmpty else { return "" }

        // Group glyphs into visual lines by their vertical centre, top to bottom.
        let byY = glyphs.sorted { $0.midY < $1.midY }
        var lines: [[Glyph]] = []
        var current: [Glyph] = [byY[0]]
        var bandY = byY[0].midY
        for g in byY.dropFirst() {
            let tolerance = max(3.0, g.height * 0.6)
            if abs(g.midY - bandY) <= tolerance {
                current.append(g)
                bandY = (bandY * CGFloat(current.count - 1) + g.midY) / CGFloat(current.count)
            } else {
                lines.append(current)
                current = [g]
                bandY = g.midY
            }
        }
        lines.append(current)

        // Within each line: left to right, re-inserting spaces where columns gap.
        return lines.map { line -> String in
            let sorted = line.sorted { $0.minX < $1.minX }
            let widths = sorted.map { $0.maxX - $0.minX }.filter { $0 > 0 }
            let avgWidth = widths.isEmpty ? 4 : widths.reduce(0, +) / CGFloat(widths.count)
            var out = ""
            var prevMaxX: CGFloat?
            for g in sorted {
                if let p = prevMaxX, g.minX - p > avgWidth * 0.5, g.s != " ", !out.hasSuffix(" ") {
                    out += " "
                }
                out += g.s
                prevMaxX = g.maxX
            }
            return out.trimmingCharacters(in: .whitespaces)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    // MARK: - Tabular parser (HDFC and similar multi-column statements)

    // With position-aware extraction each transaction's first visual line reads, left to
    // right, as the full row:
    //   "16/06/26 UPI-AUTOPAY-CRED 0000653329026808 16/06/26 300.00 45,965.86"
    //   <txnDate>  <narration ……………………………………>      <valueDt> <amount> <closing>
    // One regex captures the whole row (this mirrors the .NET/PdfPig parser). Debit vs
    // credit is inferred from the closing-balance trend; this is an expense tracker, so
    // only debits are returned.
    private func parseTabular(from text: String) -> [ParsedExpense]? {
        guard let rowRe = try? NSRegularExpression(
            pattern: #"(\d{2}/\d{2}/\d{2,4})\s+(.+?)\s+(\d{2}/\d{2}/\d{2,4})\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})"#
        ) else { return nil }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        struct Row { let date: Date; let narration: String; let amount: Double; let closing: Double }
        var rows: [Row] = []
        var seen = Set<String>()

        for m in rowRe.matches(in: text, range: fullRange) {
            let dateStr = ns.substring(with: m.range(at: 1))
            let rawNarr = ns.substring(with: m.range(at: 2))
            let amtStr  = ns.substring(with: m.range(at: 4)).replacingOccurrences(of: ",", with: "")
            let balStr  = ns.substring(with: m.range(at: 5)).replacingOccurrences(of: ",", with: "")

            guard let date = parseDate(dateStr),
                  let amount = Double(amtStr), amount > 1,
                  let closing = Double(balStr) else { continue }

            let narration = cleanNarration(rawNarr)
            let key = "\(Int(date.timeIntervalSince1970))|\(amtStr)|\(narration)"
            guard seen.insert(key).inserted else { continue }
            rows.append(Row(date: date, narration: narration, amount: amount, closing: closing))
        }

        guard rows.count >= 2 else { return nil }

        var expenses: [ParsedExpense] = []
        for (i, row) in rows.enumerated() {
            // Balance fell vs the previous row → money left the account → debit.
            // The first row has no predecessor; infer its direction from the next row.
            let isDebit = i == 0 ? row.closing >= rows[1].closing : row.closing < rows[i - 1].closing
            guard isDebit else { continue }
            let merchant = row.narration.count > 1 ? row.narration : "Bank Transaction"
            expenses.append(ParsedExpense(amount: row.amount, merchant: merchant,
                                          paymentMethod: .other, transactionDate: row.date, bankName: nil))
        }
        return expenses
    }

    // Extract a clean merchant name from a raw UPI/ACH/NEFT narration string.
    private func cleanNarration(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip the channel prefix.
        for prefix in ["UPI-", "UPI/", "ACH D-", "ACH D -", "NEFT-", "RTGS-", "IMPS-", "POS-"] {
            if s.uppercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // UPI "NAME-vpa@bank" form → keep NAME (the segment before the VPA handle).
        if let at = s.firstIndex(of: "@") {
            let beforeAt = String(s[..<at])
            s = beforeAt.lastIndex(of: "-").map { String(beforeAt[..<$0]) } ?? beforeAt
        }

        // Drop a trailing reference number and anything after it.
        if let cut = s.range(of: #"\s*\d{6,}.*$"#, options: .regularExpression) {
            s = String(s[..<cut.lowerBound])
        }

        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-/ "))
        if s == s.uppercased() && s.count > 2 { s = s.capitalized }
        return s
    }

    // MARK: - Line-by-line fallback (non-tabular PDFs)

    private func parseLineByLine(from text: String) -> [ParsedExpense] {
        text.components(separatedBy: .newlines).compactMap { parseTransactionLine($0) }
    }

    private func parseTransactionLine(_ line: String) -> ParsedExpense? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return nil }

        let datePatterns = [
            "^(\\d{2}/\\d{2}/\\d{2,4})",
            "^(\\d{2}-\\d{2}-\\d{4})",
            "^(\\d{2}-[A-Za-z]{3}-\\d{2,4})",
            "^(\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4})",
        ]

        var date: Date?
        var rest = trimmed

        for pattern in datePatterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let ns = trimmed as NSString
            if let m = re.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
               let r = Range(m.range(at: 1), in: trimmed) {
                date = parseDate(String(trimmed[r]))
                rest = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard date != nil else { return nil }

        let lower = rest.lowercased()
        if lower.hasSuffix(" cr") || lower.hasSuffix("(cr)") { return nil }
        if lower.contains("interest credit") || lower.contains("salary credit") { return nil }

        guard let amtRe = try? NSRegularExpression(pattern: "([\\d,]+\\.\\d{2})", options: []) else { return nil }
        let nsRest = rest as NSString
        let amtMatches = amtRe.matches(in: rest, range: NSRange(location: 0, length: nsRest.length))
        guard let firstAmt = amtMatches.first,
              let amtRange = Range(firstAmt.range(at: 1), in: rest) else { return nil }

        let amtStr = String(rest[amtRange]).replacingOccurrences(of: ",", with: "")
        guard let amount = Double(amtStr), amount > 1 else { return nil }

        var description = String(rest[..<amtRange.lowerBound])
            .replacingOccurrences(of: "\\b\\d{9,}\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard description.count > 2 else { return nil }

        for prefix in ["UPI/", "UPI-", "NEFT/", "NEFT-", "IMPS/", "POS/"] {
            if description.uppercased().hasPrefix(prefix) {
                description = String(description.dropFirst(prefix.count))
                description = description.components(separatedBy: "/").first ?? description
                description = description.components(separatedBy: "-").first ?? description
                break
            }
        }

        description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description == description.uppercased(), description.count > 2 { description = description.capitalized }
        guard !description.isEmpty else { return nil }

        return ParsedExpense(amount: amount, merchant: description,
                             paymentMethod: .other, transactionDate: date ?? Date(), bankName: nil)
    }

    // MARK: - Date parsing

    private func parseDate(_ str: String) -> Date? {
        let s = str.trimmingCharacters(in: .whitespaces)
        let specs: [(String, String)] = [
            ("dd/MM/yy",   "en_US_POSIX"),
            ("dd/MM/yyyy", "en_US_POSIX"),
            ("dd-MM-yyyy", "en_US_POSIX"),
            ("dd-MMM-yy",  "en_US"),
            ("dd-MMM-yyyy","en_US"),
            ("dd MMM yyyy","en_US"),
        ]
        for (fmt, locale) in specs {
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: locale)
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
