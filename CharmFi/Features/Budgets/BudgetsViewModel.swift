import Foundation
import Observation

@Observable
@MainActor
final class BudgetsViewModel: AuthedViewModel {
    var budgets: [Budget] = []
    var tripBudgets: [Budget] = []
    var categories: [Category] = []
    var categorySpending: [String: Double] = [:]
    var isLoading = false
    var error: String?
    var selectedTab = 0

    // Global monthly settings
    var cycleDay = 1

    // Month selector + This month/Defaults toggle (monthly tab only)
    var period: DashboardPeriod = DashboardPeriod.current().withMode(.month)
    var viewMode: BudgetViewMode = .month

    // Map categoryId → Budget (nil key = overall budget)
    var budgetMap: [String?: Budget] = [:]
    var tripBudgetMap: [String?: Budget] = [:]

    private let budgetService: BudgetService
    private let categoryService: CategoryService

    init(auth: AuthState) {
        budgetService = BudgetService(auth: auth)
        categoryService = CategoryService(auth: auth)
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

    private var isTripTab: Bool { selectedTab == 1 }

    /// Whether a given row can be edited right now. Trips and defaults are month-independent, so
    /// they are always editable — a past month must still let you change what applies to every
    /// month. Otherwise the server's per-budget `isEditable` is authoritative (rows can have
    /// different cycle start days, so the page-wide `cycleEditable` heuristic can be wrong for
    /// some of them); that heuristic is the fallback only when no row exists yet.
    /// Mirrors Android's `BudgetRowCtx.editable` (BudgetsScreen.kt).
    func rowEditable(_ budget: Budget?) -> Bool {
        if isTripTab || viewMode == .defaults { return true }
        return budget?.isEditable ?? cycleEditable
    }

    /// The budget did not exist in this month — never merely "no override for this month".
    /// Such a row shows the raw spend and no utilization bar, because there was nothing to spend
    /// against. Defaults mode has no month, so it never applies.
    func rowNotSet(_ budget: Budget?) -> Bool {
        guard let budget, !isTripTab, viewMode == .month else { return false }
        return budget.isBeforeStart
    }

    /// A month the budget did not cover has no utilization to show.
    func rowShowsBar(_ budget: Budget) -> Bool { !budget.isBeforeStart }

    /// Show the bare spend figure when no budget covers this month. Spending still happened.
    func rowShowsRawSpend(_ budget: Budget?) -> Bool { budget == nil || rowNotSet(budget) }

    /// The default in Defaults mode, otherwise the viewed month's amount.
    func displayAmount(_ budget: Budget) -> Double {
        !isTripTab && viewMode == .defaults ? budget.defaultAmount : budget.effectiveAmount
    }

    /// How this month's amount came about, shown as a chip beside it. Defaults mode is
    /// month-independent and trips have no cycles, so neither carries one.
    func chip(_ budget: Budget) -> BudgetChip? {
        if isTripTab || viewMode == .defaults || budget.isBeforeStart { return nil }
        if !budget.isEditable { return .frozen }
        return budget.isOverridden ? .custom : .default
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
            // Hydrate the cycle day from the overall budget. Without this the sheet always posts
            // day 1, which would re-base a budget whose real cycle day differs and orphan its
            // recorded months. Mirrors Android's `LaunchedEffect(monthlyMap)`.
            if let overall = budgetMap[nil], overall.isMonthly {
                cycleDay = overall.cycleStartDay
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

    func createBudget(_ req: BudgetRequest) async {
        do {
            try await budgetService.createBudget(req)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func updateBudget(id: String, req: BudgetRequest) async {
        do {
            try await budgetService.updateBudget(id: id, req: req)
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

    // Trips across every bucket, each tagged with whether its bucket is the shared one.
    struct TripEntry: Identifiable {
        let category: Category
        let isShared: Bool
        var id: String { category.id }
    }
    var tripEntries: [TripEntry] {
        categories.tripBuckets().flatMap { bucket in
            let shared = categories.isSharedTripBucket(bucket)
            return bucket.children.map { TripEntry(category: $0, isShared: shared) }
        }
    }

    /// Categories offered on the monthly-planning tab: excluded subtrees (transfers, card
    /// payments) and every Trips & Events bucket are pruned out — the server rejects budgets set
    /// on either, so the monthly tree shouldn't offer "Set" on them. Mirrors Android's
    /// `pruneTrips(pruneExcluded(categories))` (BudgetsScreen.kt).
    var monthlyCategories: [Category] {
        categories.pruneExcluded().pruneTrips()
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

/// Why the amount on a monthly row is what it is: the month has ended and is read-only, an
/// explicit per-month amount overrides the default, or the default simply applies.
enum BudgetChip {
    case frozen, custom, `default`
}
