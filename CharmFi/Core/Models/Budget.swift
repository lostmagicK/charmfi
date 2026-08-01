import Foundation

struct Budget: Codable, Identifiable {
    let id: String
    var name: String
    var defaultAmount: Double
    var currency: String
    var categoryId: String?
    var categoryName: String?
    var parentBudgetId: String?
    var isMonthly: Bool
    var cycleStartDay: Int
    var startDate: Date?
    var endDate: Date?
    var rolloverEnabled: Bool
    var effectiveAmount: Double
    var spent: Double
    var remaining: Double
    var cycleStart: Date?
    var cycleEnd: Date?
    var children: [Budget]
    var cycleBaseAmount: Double
    var cycleExists: Bool
    /// The month precedes the budget's first cycle: render "not set", no utilization bar.
    var isBeforeStart: Bool = false
    /// This month hasn't ended yet, so it may still be edited.
    var isEditable: Bool = true
    /// An explicit per-month amount differing from the default applies.
    var isOverridden: Bool = false
    var firstCycleStart: Date?
    var categorySpending: [String: Double]?
}

struct BudgetCycle: Codable, Identifiable {
    let id: String
    let budgetId: String?
    let cycleStartDate: Date
    let cycleEndDate: Date
    var baseAmount: Double
    var rolloverAmount: Double
    var effectiveAmount: Double
    var spent: Double
}

struct BudgetRequest: Encodable {
    var name: String
    var defaultAmount: Double
    var currency: String = "INR"
    var categoryId: String?
    var parentBudgetId: String?
    var isMonthly: Bool = true
    var cycleStartDay: Int = 1
    var startDate: Date?
    var endDate: Date?
    var rolloverEnabled: Bool = false
}

struct UpdateCycleRequest: Encodable {
    var baseAmount: Double
}

struct BudgetCycleCreateRequest: Encodable {
    var budgetId: String
    var year: Int
    var month: Int
    var baseAmount: Double
}
