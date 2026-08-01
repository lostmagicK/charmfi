import Foundation

struct GmailMessage {
    let id: String
    let subject: String
    let body: String
    let receivedDate: Date
    let fromAddress: String
}

final class GmailFetchService: @unchecked Sendable {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20   // per-request timeout
        config.timeoutIntervalForResource = 60  // total resource timeout
        return URLSession(configuration: config)
    }()

    func listMessageIds(accessToken: String, query: String, sinceDate: Date?) async throws -> [String] {
        var q = query
        if let since = sinceDate {
            q += " after:\(Int(since.timeIntervalSince1970))"
        }

        var allIds: [String] = []
        var nextPageToken: String?

        repeat {
            var components = URLComponents(string: "\(baseURL)/messages")!
            var queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "maxResults", value: "100")]
            if let token = nextPageToken { queryItems.append(.init(name: "pageToken", value: token)) }
            components.queryItems = queryItems

            var req = URLRequest(url: components.url!)
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await session.data(for: req)

            let result = try JSONDecoder().decode(MessageListResponse.self, from: data)
            allIds += result.messages?.map(\.id) ?? []
            nextPageToken = result.nextPageToken
        } while nextPageToken != nil

        return allIds
    }

    func getMessage(accessToken: String, messageId: String) async throws -> GmailMessage {
        var req = URLRequest(url: URL(string: "\(baseURL)/messages/\(messageId)?format=full")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: req)

        let raw = try JSONDecoder().decode(RawGmailMessage.self, from: data)
        let subject = raw.payload?.headers?.first(where: { $0.name.lowercased() == "subject" })?.value ?? ""
        let from = raw.payload?.headers?.first(where: { $0.name.lowercased() == "from" })?.value ?? ""
        let plain = extractPlainText(from: raw.payload) ?? ""
        let date = Date(timeIntervalSince1970: Double(raw.internalDate ?? "0")! / 1000)

        // Mirror the backend: patterns run against "From: …\nSubject: …\n\n<plain text>"
        // so subject/from-based regexes match the same input the server uses.
        var combined = ""
        if !from.isEmpty { combined += "From: \(from)\n" }
        if !subject.isEmpty { combined += "Subject: \(subject)\n" }
        if !combined.isEmpty { combined += "\n" }
        combined += plain

        return GmailMessage(id: messageId, subject: subject, body: combined, receivedDate: date, fromAddress: from)
    }

    // Recurse the MIME tree, preferring text/plain and falling back to HTML
    // (stripped to text). Matches the backend's ExtractPlainText behavior.
    private func extractPlainText(from payload: RawPayload?) -> String? {
        guard let payload else { return nil }
        let mime = payload.mimeType ?? ""
        if mime == "text/plain" || mime == "text/html", let data = payload.body?.data {
            let text = decodeBase64URL(data)
            return mime == "text/html" ? stripHtml(text) : text
        }
        if let parts = payload.parts {
            // First pass: prefer text/plain anywhere in the subtree
            for part in parts where (part.mimeType ?? "") == "text/plain" {
                if let t = extractPlainText(from: part) { return t }
            }
            // Second pass: any part (nested multipart / html)
            for part in parts {
                if let t = extractPlainText(from: part) { return t }
            }
        }
        return nil
    }

    private func decodeBase64URL(_ base64url: String) -> String {
        var base64 = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Mirrors the backend's StripHtml: drop content-free blocks, turn block-level
    // tags into line breaks, remove remaining tags, decode entities, and collapse
    // runs of blank lines.
    private func stripHtml(_ html: String) -> String {
        var s = html
        func replace(_ pattern: String, with replacement: String,
                     options: NSRegularExpression.Options = [.caseInsensitive]) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                            withTemplate: replacement)
        }

        replace("<style[\\s\\S]*?</style>", with: "")
        replace("<script[\\s\\S]*?</script>", with: "")
        replace("<head[\\s\\S]*?</head>", with: "")
        replace("<!--[\\s\\S]*?-->", with: "")
        // Bare CSS rulesets that leaked out of <style>; run twice for nesting
        for _ in 0..<2 {
            replace("@?[a-zA-Z][^{};]*\\{[^{}]*\\}", with: "",
                    options: [.caseInsensitive, .dotMatchesLineSeparators])
        }
        replace("<(p|div|table|tr|ul|ol|blockquote|h[1-6])\\b[^>]*>", with: "\n\n")
        replace("</(p|div|table|tr|ul|ol|blockquote|h[1-6])>", with: "\n\n")
        replace("<br\\s*/?>", with: "\n")
        replace("<td\\b[^>]*>", with: "  ")
        replace("<li\\b[^>]*>", with: "\n• ")
        replace("<[^>]+>", with: "")

        s = decodeHtmlEntities(s)

        // Collapse 2+ blank lines to one, trim trailing whitespace per line.
        var out: [String] = []
        var blanks = 0
        for rawLine in s.components(separatedBy: "\n") {
            let line = String(rawLine.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
            if line.isEmpty {
                blanks += 1
                if blanks <= 1 { out.append("") }
            } else {
                blanks = 0
                out.append(line)
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHtmlEntities(_ text: String) -> String {
        var s = text
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
            "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
            "&rdquo;": "\u{201D}", "&ldquo;": "\u{201C}",
            "&ndash;": "\u{2013}", "&mdash;": "\u{2014}", "&hellip;": "\u{2026}"
        ]
        for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }

        // Numeric entities: &#1234; and &#x1F4;
        guard let re = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") else { return s }
        let ns = s as NSString
        var result = ""
        var lastEnd = 0
        re.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let isHex = ns.substring(with: match.range(at: 1)) == "x"
            let digits = ns.substring(with: match.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = UnicodeScalar(code) {
                result += String(scalar)
            }
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }
}

// MARK: - Gmail API Decodable types

private struct MessageListResponse: Decodable {
    let messages: [MessageRef]?
    let nextPageToken: String?
}

private struct MessageRef: Decodable {
    let id: String
}

private struct RawGmailMessage: Decodable {
    let id: String
    let internalDate: String?
    let payload: RawPayload?
}

private struct RawPayload: Decodable {
    let mimeType: String?
    let headers: [RawHeader]?
    let body: RawBody?
    let parts: [RawPayload]?
}

private struct RawHeader: Decodable {
    let name: String
    let value: String
}

private struct RawBody: Decodable {
    let data: String?
}
