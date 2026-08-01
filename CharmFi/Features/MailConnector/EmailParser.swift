import Foundation

struct ParsedExpense {
    let amount: Double
    let merchant: String
    let paymentMethod: PaymentMethod
    let transactionDate: Date
    let bankName: String?
}

struct EmailParser {
    // Domain-based keywords (match From: header) come first — most specific.
    // Body-text keywords follow as fallback. Mirrors the backend's DetectBankName
    // (GmailSyncHandler.cs) so both sides agree on the same canonical short names.
    private let bankKeywords: [(keyword: String, bankName: String)] = [
        ("federalbank.co.in", "Federal Bank"),
        ("axisbank.com",      "Axis"),
        ("hdfcbank.com",      "HDFC"),
        ("icicibank.com",     "ICICI"),
        ("sbi.co.in",         "SBI"),
        ("kotak.com",         "Kotak"),
        ("yesbank.in",        "Yes Bank"),
        ("indusind.com",      "IndusInd"),
        ("bankofbaroda.com",  "BOB"),
        ("canarabank.in",     "Canara"),
        ("pnbindia.in",       "PNB"),
        ("bankofindia.co.in", "BOI"),
        ("federal bank",      "Federal Bank"),
        ("fedfina",           "Federal Bank"),
        ("hdfc bank",         "HDFC"),
        ("icici bank",        "ICICI"),
        ("state bank",        "SBI"),
        ("axis bank",         "Axis"),
        ("kotak mahindra",    "Kotak"),
        ("yes bank",          "Yes Bank"),
        ("indusind bank",     "IndusInd"),
        ("bank of baroda",    "BOB"),
        ("canara bank",       "Canara"),
        ("punjab national",   "PNB"),
        ("bank of india",     "BOI"),
    ]

    private func detectBank(in text: String) -> String? {
        let lower = text.lowercased()
        for (keyword, bankName) in bankKeywords where lower.contains(keyword) {
            return bankName
        }
        return nil
    }

    // Tolerant compare: pattern banks may use short forms ("HDFC") while others use
    // full names ("HDFC Bank") — accept either containing the other.
    private func bankMatches(_ patternBank: String?, _ messageBank: String) -> Bool {
        guard let patternBank, !patternBank.isEmpty else { return false }
        return patternBank.localizedCaseInsensitiveContains(messageBank) ||
            messageBank.localizedCaseInsensitiveContains(patternBank)
    }

    func parse(message: GmailMessage, patterns: [EmailPattern]) -> ParsedExpense? {
        // `message.body` is the combined "From: …\nSubject: …\n\n<plain text>" the
        // backend builds — every regex runs against it, exactly like the server.
        let text = message.body
        let messageBank = detectBank(in: text)

        // Bank-matched patterns first, then generic (no bank set), then the rest —
        // never worse than the unordered scan, just prefers the right bank when known.
        let orderedPatterns: [EmailPattern]
        if let messageBank {
            orderedPatterns = patterns.sorted { a, b in
                rank(for: a.bankName, messageBank: messageBank) < rank(for: b.bankName, messageBank: messageBank)
            }
        } else {
            orderedPatterns = patterns
        }

        for pattern in orderedPatterns {
            if let subject = pattern.subjectRegex, !subject.isEmpty {
                guard matches(text: text, regex: subject) else { continue }
            }
            guard let amountStr = extract(from: text, regex: pattern.amountRegex) else { continue }
            guard let amount = parseAmount(amountStr), amount > 0 else { continue }

            var merchant = "Unknown"
            if let mr = pattern.merchantRegex, !mr.isEmpty,
               let captured = extract(from: text, regex: mr) {
                merchant = cleanMerchant(captured)
            }

            let dateStr = pattern.dateRegex.flatMap { $0.isEmpty ? nil : extract(from: text, regex: $0) }
            let date = dateStr.flatMap { parseDate($0) } ?? message.receivedDate

            let method = PaymentMethod(rawValue: pattern.paymentMethod) ?? .other
            return ParsedExpense(amount: amount, merchant: merchant, paymentMethod: method,
                                  transactionDate: date, bankName: messageBank)
        }
        return nil
    }

    private func rank(for patternBank: String?, messageBank: String) -> Int {
        if bankMatches(patternBank, messageBank) { return 0 }
        return patternBank == nil ? 1 : 2
    }

    private let regexOptions: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

    private func matches(text: String, regex: String) -> Bool {
        guard let r = try? NSRegularExpression(pattern: regex, options: regexOptions) else { return false }
        return r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func extract(from text: String, regex: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: regex, options: regexOptions) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = r.firstMatch(in: text, range: range) else { return nil }
        if match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: text) {
            return String(text[captureRange]).trimmingCharacters(in: .whitespaces)
        }
        if let fullRange = Range(match.range, in: text) {
            return String(text[fullRange]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func parseAmount(_ str: String) -> Double? {
        // Strip everything except digits and the decimal point
        let cleaned = str.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        return Double(cleaned)
    }

    private func parseDate(_ str: String) -> Date? {
        let formatters = [
            "dd/MM/yyyy", "dd-MM-yyyy", "yyyy-MM-dd",
            "dd MMM yyyy", "MMM dd, yyyy", "d MMM yyyy"
        ].map { format -> DateFormatter in
            let f = DateFormatter()
            f.dateFormat = format
            return f
        }
        for f in formatters {
            if let date = f.date(from: str) { return date }
        }
        return nil
    }

    // Mirrors the backend's CleanMerchant: trim trailing punctuation, drop the
    // domain from a bare email, and title-case all-caps merchant names.
    private func cleanMerchant(_ raw: String) -> String {
        // Regex runs with .dotMatchesLineSeparators so captures can span lines;
        // take only the first non-empty line — a merchant name is always one line.
        let firstLine = raw.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? raw

        var cleaned = firstLine
            .replacingOccurrences(of: "[\\r\\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = cleaned.last, ".,;:".contains(last) { cleaned.removeLast() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.contains("@"), !cleaned.contains(" ") {
            cleaned = String(cleaned.split(separator: "@").first ?? "")
        }
        if cleaned == cleaned.uppercased(), cleaned.count > 2 {
            cleaned = cleaned.capitalized
        }
        return cleaned
    }
}
