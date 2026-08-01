import Foundation
import Observation

@Observable
@MainActor
final class BudgetsViewModel {
    var budgets: [Budget] = []
    var tripBudgets: [Budget] = []
    var categories: [Category] = []
    var categorySpending: [String: Double] = [:]
    var isLoading = false
    var error: String?
    var selectedTab = 0

    // Global monthly settings
    var cycleDay = 1
    var rollover = false

    // Month selector + This month/Defaults toggle (monthly tab only)
    var period: DashboardPeriod = DashboardPeriod.current().withMode(.month)
    var viewMode: BudgetViewMode = .month

    // Map categoryId → Budget (nil key = overall budget)
    var budgetMap: [String?: Budget] = [:]
    var tripBudgetMap: [String?: Budget] = [:]

    // Accordion expanded state
    var expandedIds: Set<String> = []

    private let budgetService: BudgetService
    private let categoryService: CategoryService
    private let expenseService: ExpenseService

    init(auth: AuthState) {
        budgetService = BudgetService(auth: auth)
        categoryService = CategoryService(auth: auth)
        expenseService = ExpenseService(auth: auth)
    }

    // Whether the currently-viewed cycle can be edited at all — derived from the overall budget's
    // own cycle end date; falls back to comparing the viewed period against the current month when
    // no overall budget exists yet.
    var cycleEditable: Bool {
        if let ob = budgetMap[nil], let end = ob.cycleEnd {
            return end > Date()
        }
        let now = DashboardPeriod.current()
        return period.year * 12 + period.month >= now.year * 12 + now.month
    }

    /// Whether a given row can be edited right now. The server sends `isEditable` per budget —
    /// authoritative when a row exists (rows can have different cycle start days, so the
    /// page-wide `cycleEditable` heuristic can be wrong for some of them). Falls back to that
    /// heuristic only when no budget row exists yet for the category.
    func rowEditable(_ budget: Budget?) -> Bool {
        budget?.isEditable ?? cycleEditable
    }

    /// Whether a row should render as "not set" (no bar, dashed placeholder) — the server's
    /// `isBeforeStart` when a row exists, else the same fallback as `rowEditable`.
    func rowNotSet(_ budget: Budget?) -> Bool {
        if let budget { return budget.isBeforeStart || !budget.cycleExists && !budget.isEditable }
        return !cycleEditable
    }

    func setPeriod(_ p: DashboardPeriod) {
        period = p
        viewMode = .month
        Task { await load() }
    }

    func load() async {
        isLoading = true
        error = nil
        async let monthlyResult  = budgetService.getBudgets(year: period.year, month: period.month)
        async let tripResult     = budgetService.getTripBudgets()
        async let spendingResult = budgetService.getCategorySpending(year: period.year, month: period.month)
        async let catsResult     = categoryService.getCategories()
        do {
            let (m, t, s, c) = try await (monthlyResult, tripResult, spendingResult, catsResult)
            budgets = m
            tripBudgets = t
            categorySpending = s
            categories = c
            buildMaps()
            // Read cycle settings from the first monthly budget
            if let first = budgets.first {
                cycleDay = first.cycleStartDay
                rollover = first.rolloverEnabled
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func buildMaps() {
        var m: [String?: Budget] = [:]
        func walk(_ budget: Budget) {
            m[budget.categoryId] = budget
            for child in budget.children { walk(child) }
        }
        for b in budgets { walk(b) }
        budgetMap = m

        var t: [String?: Budget] = [:]
        func walkTrip(_ budget: Budget) {
            t[budget.categoryId] = budget
            for child in budget.children { walkTrip(child) }
        }
        for b in tripBudgets { walkTrip(b) }
        tripBudgetMap = t
    }

    func toggleExpanded(_ id: String) {
        if expandedIds.contains(id) { expandedIds.remove(id) }
        else { expandedIds.insert(id) }
    }

    func createBudget(_ req: BudgetRequest) async {
        do {
            _ = try await budgetService.createBudget(req)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func updateBudget(id: String, req: BudgetRequest) async {
        do {
            _ = try await budgetService.updateBudget(id: id, req: req)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    // Month mode on an already-existing monthly budget edits only this cycle's amount
    func upsertCycleAmount(budgetId: String, amount: Double) async {
        do {
            try await budgetService.upsertCycle(budgetId: budgetId, year: period.year, month: period.month, amount: amount)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func deleteBudget(id: String) async {
        do {
            try await budgetService.deleteBudget(id: id)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    // Spent recursively through all children
    func spentRecursive(_ cat: Category) -> Double {
        let own = categorySpending[cat.id] ?? 0
        return own + cat.children.map { spentRecursive($0) }.reduce(0, +)
    }

    // Trip root category (global category named "Trip")
    var tripRoot: Category? {
        categories.first(where: { $0.name == "Trip" && $0.isGlobal })
    }
    var tripL2s: [Category] { tripRoot?.children ?? [] }

    /// Categories offered on the monthly-planning tab: excluded subtrees (transfers, card
    /// payments) and the Trip bucket are pruned out — the server rejects budgets set on either,
    /// so the monthly tree shouldn't offer "Set" on them. Mirrors Android's
    /// `pruneTrips(pruneExcluded(categories))` (BudgetsScreen.kt).
    var monthlyCategories: [Category] {
        categories.pruneExcluded().filter { !($0.name == "Trip" && $0.isGlobal) }
    }

    // The amount a budget contributes to parent/child sum checks while editing — mode-aware for the
    // monthly tab (this month's cycle base vs. the default), effectiveAmount for trips (unchanged).
    private func amountFor(_ b: Budget?, isTrip: Bool) -> Double {
        guard let b else { return 0 }
        if isTrip { return b.effectiveAmount }
        return viewMode == .defaults ? b.defaultAmount : b.cycleBaseAmount
    }

    private func findParentCategory(_ categoryId: String) -> Category? {
        func search(_ cats: [Category]) -> Category? {
            for cat in cats {
                if cat.children.contains(where: { $0.id == categoryId }) { return cat }
                if let found = search(cat.children) { return found }
            }
            return nil
        }
        return search(categories)
    }

    // Max allowed = parent budget's amount minus siblings already allocated; L1 categories fall
    // back to the overall budget as their parent.
    func maxAllowed(for categoryId: String?, isTrip: Bool) -> Double? {
        guard let categoryId else { return nil } // overall — no parent constraint
        let map = isTrip ? tripBudgetMap : budgetMap
        let parentBudget: Budget?
        let siblingCats: [Category]
        if let parentCat = findParentCategory(categoryId) {
            parentBudget = map[parentCat.id]
            siblingCats = parentCat.children
        } else if isTrip {
            return nil // Trip L2 has no budget parent
        } else {
            parentBudget = map[nil]
            siblingCats = categories // L1 categories, parent = overall budget
        }
        guard let parentBudget else { return nil }
        let siblingAllocated = siblingCats.filter { $0.id != categoryId }
            .reduce(0.0) { $0 + amountFor(map[$1.id], isTrip: isTrip) }
        return max(0, amountFor(parentBudget, isTrip: isTrip) - siblingAllocated)
    }
}

enum BudgetViewMode {
    case month, defaults
}
