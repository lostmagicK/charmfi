import Foundation

struct HouseholdDailyPoint: Codable, Identifiable {
    var id: Int { day }
    let day: Int
    let total: Double
}

struct HouseholdSummary: Codable {
    var totalThisMonth: Double
    var totalThisYear: Double
    var transactionCountThisMonth: Int
    var myAmountThisMonth: Double
    var sharedAmountThisMonth: Double
    var myAmountThisYear: Double
    var byMember: [HouseholdMemberSummary]
    var bySubcategory: [HouseholdSubcategorySummary]
    var byCategoryHierarchy: [HouseholdCategoryGroup] = []
    var monthlyTrend: [HouseholdMonthlyPoint]
    var recent: [HouseholdExpenseItem]
}

struct HouseholdMemberSummary: Codable, Identifiable {
    var id: String { userId }
    var userId: String
    var displayName: String
    var isOwn: Bool
    var totalThisMonth: Double
}

struct HouseholdSubcategorySummary: Codable, Identifiable {
    var id: String { categoryId }
    var categoryId: String
    var name: String
    var icon: String?
    var total: Double
    var count: Int
}

struct HouseholdCategoryGroup: Codable, Identifiable {
    var id: String { categoryId }
    var categoryId: String
    var name: String
    var icon: String?
    var total: Double
    var count: Int
    var subcategories: [HouseholdSubcategorySummary]
}

struct HouseholdMonthlyPoint: Codable, Identifiable {
    var id: String { month }
    var month: String      // e.g. "2024-01"
    var myAmount: Double
    var sharedAmount: Double

    var shortLabel: String {
        // month is "YYYY-MM" — return last 3 chars of month name
        let parts = month.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]) else { return month }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.shortMonthSymbols[m - 1]
    }
}

struct HouseholdExpenseItem: Codable, Identifiable {
    var id: String
    var ownerUserId: String
    var ownerDisplayName: String
    var isOwn: Bool
    var amount: Double
    var currency: String
    var merchant: String
    var transactionDate: String   // kept as String (matches Android)
    var categoryName: String?
    var categoryIcon: String?
    var parentCategoryName: String?
    var paymentMethod: String
}

struct HouseholdExpenseFilters {
    var from: Date?
    var to: Date?
    var ownerUserId: String?
    var categoryId: String?
    var search: String?
    var paymentMethod: PaymentMethod?
    var page: Int = 1
    var pageSize: Int = 20

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        let fmt = ISO8601DateFormatter()
        if let from { items.append(.init(name: "dateFrom", value: fmt.string(from: from))) }
        if let to { items.append(.init(name: "dateTo", value: fmt.string(from: to))) }
        if let ownerUserId { items.append(.init(name: "ownerUserId", value: ownerUserId)) }
        if let categoryId { items.append(.init(name: "categoryId", value: categoryId)) }
        if let search, !search.isEmpty { items.append(.init(name: "search", value: search)) }
        if let pm = paymentMethod { items.append(.init(name: "paymentMethod", value: pm.rawValue)) }
        items.append(.init(name: "page", value: "\(page)"))
        items.append(.init(name: "pageSize", value: "\(pageSize)"))
        return items
    }
}
