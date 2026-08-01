import Foundation

struct Expense: Codable, Identifiable, Sendable {
    let id: String
    let amount: Double
    var currency: String?         // optional — server may omit on drafts
    let merchant: String
    var paymentMethod: PaymentMethod
    var transactionDate: Date
    var source: ExpenseSource?    // optional — not always returned
    var status: ExpenseStatus?    // optional — not always returned
    var comment: String?
    var rawSmsText: String?
    var paymentAccountId: String?
    var categoryId: String?
    var categoryName: String?
    var sharedByUserId: String?
    var sharedByDisplayName: String?
    var createdAt: Date?
    /// Tags set directly on the transaction, by the user or stamped by a merchant rule.
    var tags: [TagRef] = []
    /// Read-only tags the transaction picks up from its category and that category's ancestors.
    var inheritedTags: [TagRef] = []
}

extension Expense {
    var allTags: [TagRef] { effectiveTags(own: tags, inherited: inheritedTags) }
}

/// An expense the current user paid on behalf of a family member — awaiting the recipient's
/// review before it's booked against their own account.
struct PaidForExpense: Codable, Identifiable, Sendable {
    let id: String
    let recipientUserId: String
    let recipientDisplayName: String
    let amount: Double
    let currency: String
    let merchant: String
    let paymentMethod: PaymentMethod
    var paymentAccountId: String?
    let transactionDate: Date
    var comment: String?
    var categoryId: String?
    let createdAt: Date
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case cash = "Cash"
    case card = "Card"
    case upi = "Upi"
    case netBanking = "NetBanking"
    case fastTag = "FastTag"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: "Cash"
        case .card: "Card"
        case .upi: "UPI"
        case .netBanking: "Net Banking"
        case .fastTag: "FASTag"
        case .other: "Other"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PaymentMethod(rawValue: raw) ?? .other
    }
}

enum ExpenseSource: String, Codable {
    case manual = "Manual"
    case sms = "Sms"
    case email = "Email"
    case pdf = "Pdf"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseSource(rawValue: raw) ?? .manual
    }
}

enum ExpenseStatus: String, Codable {
    case draft = "Draft"
    case submitted = "Submitted"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseStatus(rawValue: raw) ?? .draft
    }
}

struct CreatedExpenseResponse: Decodable, Sendable {
    let id: String
}

// A draft sent to /expenses/check-duplicates. Key is the draft's own id, echoed
// back in duplicateKeys so the client knows which drafts match a booked expense.
struct DuplicateCandidateRequest: Encodable, Sendable {
    let key: String
    let transactionDate: Date
    let amount: Double
    let paymentMethod: PaymentMethod
}

struct CheckDuplicatesResponse: Decodable, Sendable {
    let duplicateKeys: [String]
}

struct PdfUploadResponse: Decodable, Sendable {
    let created: Int
    let message: String
}

struct PagedResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let total: Int
    let page: Int
    let pageSize: Int
    var totalAmount: Double?
}

// MARK: - Request types

struct CreateExpenseRequest: Encodable, Sendable {
    var amount: Double
    var currency: String = "INR"
    var merchant: String
    var paymentMethod: PaymentMethod
    var transactionDate: Date
    var source: ExpenseSource = .manual
    var status: ExpenseStatus = .draft
    var comment: String?
    var categoryId: String?
    var paymentAccountId: String?
    var rawSmsText: String?
    var sharedByUserId: String?
}

struct UpdateExpenseRequest: Encodable, Sendable {
    var amount: Double?
    var merchant: String?
    var paymentMethod: PaymentMethod?
    var transactionDate: Date?
    var comment: String?
    var categoryId: String?
    var paymentAccountId: String?
}

struct ExpenseFilters: Sendable {
    var from: Date?
    var to: Date?
    var categoryId: String?
    var search: String?
    var paymentMethod: PaymentMethod?
    var paymentAccountId: String?
    var status: ExpenseStatus?
    var sortBy: String = "transactionDate"
    var sortDesc: Bool = true
    var page: Int = 1
    var pageSize: Int = 20

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        let formatter = ISO8601DateFormatter()
        if let from { items.append(.init(name: "from", value: formatter.string(from: from))) }
        if let to { items.append(.init(name: "to", value: formatter.string(from: to))) }
        if let categoryId { items.append(.init(name: "categoryId", value: categoryId)) }
        if let search, !search.isEmpty { items.append(.init(name: "search", value: search)) }
        if let paymentMethod { items.append(.init(name: "paymentMethod", value: paymentMethod.rawValue)) }
        if let paymentAccountId { items.append(.init(name: "paymentAccountId", value: paymentAccountId)) }
        if let status { items.append(.init(name: "status", value: status.rawValue)) }
        items.append(.init(name: "sortBy", value: sortBy))
        items.append(.init(name: "sortDesc", value: sortDesc ? "true" : "false"))
        items.append(.init(name: "page", value: "\(page)"))
        items.append(.init(name: "pageSize", value: "\(pageSize)"))
        return items
    }
}
