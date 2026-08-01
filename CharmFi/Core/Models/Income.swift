import Foundation

enum IncomeKind: String, Codable, CaseIterable, Identifiable {
    case fixed = "Fixed"
    case variable = "Variable"

    var id: String { rawValue }
    var displayName: String { self == .fixed ? "Fixed" : "Variable" }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IncomeKind(rawValue: raw) ?? .variable
    }
}

struct IncomeSource: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var kind: IncomeKind
    var defaultAmount: Double
    var currency: String
    var dayOfMonth: Int?
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
    var icon: String?
    var color: String?
    var sortOrder: Int
}

struct IncomeSourceRequest: Encodable, Sendable {
    var name: String
    var kind: IncomeKind
    var defaultAmount: Double
    var currency: String = "INR"
    var dayOfMonth: Int?
    var startDate: Date
    var endDate: Date?
    var icon: String?
    var color: String?
    var sortOrder: Int = 0
    var isActive: Bool = true
}

struct IncomeSourceAmount: Codable, Identifiable, Sendable {
    let sourceId: String
    let name: String
    let kind: IncomeKind
    let icon: String?
    let color: String?
    let amount: Double

    var id: String { sourceId }
}

struct IncomeEntry: Codable, Identifiable, Sendable {
    let id: String
    let incomeSourceId: String
    let sourceName: String
    let kind: IncomeKind
    var amount: Double
    var currency: String
    var receivedOn: Date
    var periodStart: Date?
    let isAutoFilled: Bool
    var note: String?
}

struct IncomeMonth: Codable, Sendable {
    let year: Int
    let month: Int
    let currency: String
    let fixedTotal: Double
    let variableTotal: Double
    let total: Double
    let bySource: [IncomeSourceAmount]
    let entries: [IncomeEntry]
}

/// One month in the trailing income summary used by the dashboard's savings-rate calculation.
struct MonthlyIncomePoint: Codable, Sendable {
    let year: Int
    let month: Int
    let fixed: Double
    let variable: Double
    let total: Double
    let bySource: [IncomeSourceAmount]
}

struct IncomeEntryRequest: Encodable, Sendable {
    var incomeSourceId: String
    var amount: Double
    var currency: String = "INR"
    var receivedOn: Date
    var note: String?
}

struct IncomeEntryUpdateRequest: Encodable, Sendable {
    var amount: Double
    var receivedOn: Date
    var note: String?
}

struct IdResponse: Decodable, Sendable {
    let id: String
}
