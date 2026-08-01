import Foundation

struct PaymentAccount: Codable, Identifiable {
    let id: String
    var name: String
    var accountType: AccountType
    var bank: String?
    var last4: String?
    var color: String?
    var linkedAccountId: String?
    var billingDay: Int?
    var isDefault: Bool
    var isActive: Bool
    var createdAt: Date?
}

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case savings = "Savings"
    case current = "Current"
    case creditCard = "CreditCard"
    case debitCard = "DebitCard"
    case wallet = "Wallet"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .savings: "Savings"
        case .current: "Current"
        case .creditCard: "Credit Card"
        case .debitCard: "Debit Card"
        case .wallet: "Wallet"
        case .other: "Other"
        }
    }

    var isCard: Bool { self == .creditCard || self == .debitCard }
    var isCredit: Bool { self == .creditCard }

    var icon: String {
        switch self {
        case .creditCard, .debitCard: "creditcard.fill"
        case .savings, .current: "building.columns.fill"
        case .wallet: "wallet.pass.fill"
        case .other: "banknote.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AccountType(rawValue: raw) ?? .other
    }
}

struct AccountStats: Codable {
    let accountId: String
    let thisMonthSpend: Double?
    let prevMonthSpend: Double?
    let lastBilledAmount: Double?
    let lastBilledAmountPrev: Double?
    let unbilledAmount: Double?
    let unbilledAmountPrev: Double?
}

struct AccountOverview: Codable {
    let totalOutstanding: Double?
    let totalUnbilled: Double?
}

struct PaymentAccountRequest: Encodable {
    var name: String
    var accountType: AccountType
    var bank: String?
    var last4: String?
    var color: String?
    var linkedAccountId: String?
    var billingDay: Int?
    var isDefault: Bool = false
    var isActive: Bool = true
}
