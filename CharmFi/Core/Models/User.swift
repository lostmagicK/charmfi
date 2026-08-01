import Foundation

struct UserProfile: Codable {
    let id: String
    var displayName: String?
    var email: String?
    var timezone: String?
    var isAdvancedUser: Bool
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, displayName, email, timezone, isAdvancedUser, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        isAdvancedUser = try c.decodeIfPresent(Bool.self, forKey: .isAdvancedUser) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct UpdateUserRequest: Encodable {
    var displayName: String?
    var timezone: String?
    var isAdvancedUser: Bool?
}

struct DashboardSummary: Codable {
    var thisMonth: Double
    var lastMonth: Double
    var thisYear: Double
    var changePercent: Double
    var creditCardOutstanding: Double?
    var creditCardUnbilled: Double?
    var monthlyTrend: [MonthlyAmount]
    var categoryBreakdown: [CategoryAmount]
    var paymentMethodBreakdown: [MethodAmount]
    var topMerchants: [MerchantAmount]
    var recentExpenses: [Expense]
}

struct MonthlyAmount: Codable, Identifiable {
    var id: String { month }
    var month: String
    var amount: Double
}

struct CategoryAmount: Codable, Identifiable {
    var id: String { categoryId ?? name }
    var categoryId: String?
    var name: String
    var amount: Double
    var count: Int
}

struct MethodAmount: Codable, Identifiable {
    var id: String { method }
    var method: String
    var amount: Double
}

struct MerchantAmount: Codable, Identifiable {
    var id: String { merchant }
    var merchant: String
    var amount: Double
    var count: Int
}
