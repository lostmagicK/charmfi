import Foundation
import Observation

// MARK: - Data models matching Android

struct MonthBar: Identifiable {
    var id: String { label }
    let label: String
    let total: Double
    let pct: Int        // 0-100, relative to max month
    let isCurrent: Bool
}

struct CategoryBar: Identifiable {
    var id: String { name }
    let name: String
    let icon: String?
    let total: Double
    let pct: Int        // 0-100, share of total
    let color: String   // hex
    var children: [CategoryBar] = []
}

struct TopMerchant: Identifiable {
    var id: String { name }
    let name: String
    let total: Double
    let count: Int
}

struct MethodBar: Identifiable {
    var id: String { method }
    let method: String
    let total: Double
    let pct: Float      // 0-1
    let color: String
}

// Cumulative running total per day-of-month, one series per period.
struct PacePoint: Identifiable {
    let id = UUID()
    let day: Int
    let amount: Double
    let period: String  // "This Month" / "Last Month"
}

struct WeekdayBar: Identifiable {
    var id: String { label }
    let label: String
    let total: Double
}

// One category's spend this period vs the previous period.
struct CategoryDelta: Identifiable {
    var id: String { name }
    let name: String
    let icon: String?
    let thisMonth: Double
    let lastMonth: Double
}

/// One stacked series on the "Saved per Month" chart — a top-level savings bucket (Equity, Debt, …)
/// plus its trailing-months values, index-aligned with `savingsTrend`/`monthlyTrend`.
struct SavingsSeries: Identifiable {
    var id: String { name }
    let name: String
    let icon: String?
    let color: String
    let values: [Double]
}

/// Saved ÷ income for one trend month. `rate` is nil (not zero) when the month has no recorded
/// income, so the savings-rate line breaks rather than dropping to the floor.
struct RatePoint: Identifiable {
    var id: String { label }
    let label: String
    let rate: Int?
    let isCurrent: Bool
}

/// Mirrors the web dashboard's SAVINGS_RATE_TARGET.
let savingsRateTargetPct = 30

let dashboardColors = [
    "#3b82f6", "#10b981", "#f59e0b", "#8b5cf6",
    "#ef4444", "#06b6d4", "#f97316", "#94a3b8"
]

private let methodColors: [String: String] = [
    "NetBanking": "#3b82f6",
    "Upi":        "#f59e0b",
    "Card":       "#8b5cf6",
    "Cash":       "#10b981",
    "FastTag":    "#06b6d4",
    "Other":      "#94a3b8"
]

// MARK: - Page-level period navigator, shared by every Dashboard tab

enum PeriodMode {
    case month, year
}

struct DashboardPeriod: Equatable, Hashable {
    var year: Int
    var month: Int
    var mode: PeriodMode

    func next() -> DashboardPeriod {
        switch mode {
        case .month:
            let comps = Calendar.current.dateComponents([.year, .month], from: Calendar.current.date(byAdding: .month, value: 1, to: periodStart)!)
            return DashboardPeriod(year: comps.year!, month: comps.month!, mode: .month)
        case .year:
            return DashboardPeriod(year: year + 1, month: month, mode: .year)
        }
    }

    func prev() -> DashboardPeriod {
        switch mode {
        case .month:
            let comps = Calendar.current.dateComponents([.year, .month], from: Calendar.current.date(byAdding: .month, value: -1, to: periodStart)!)
            return DashboardPeriod(year: comps.year!, month: comps.month!, mode: .month)
        case .year:
            return DashboardPeriod(year: year - 1, month: month, mode: .year)
        }
    }

    func withMode(_ newMode: PeriodMode) -> DashboardPeriod {
        DashboardPeriod(year: year, month: month, mode: newMode)
    }

    /// True once this period reaches the actual current month/year — next() should be disabled.
    var isAtPresent: Bool {
        let cal = Calendar.current
        let now = Date()
        let nowYear = cal.component(.year, from: now)
        let nowMonth = cal.component(.month, from: now)
        return mode == .month ? (year == nowYear && month == nowMonth) : (year == nowYear)
    }

    var label: String {
        switch mode {
        case .month:
            let f = DateFormatter()
            f.dateFormat = "MMM yyyy"
            return f.string(from: periodStart)
        case .year:
            return "\(year)"
        }
    }

    var periodStart: Date {
        Calendar.current.date(from: DateComponents(year: year, month: mode == .month ? month : 1, day: 1))!
    }
    var periodEnd: Date {
        Calendar.current.date(byAdding: mode == .month ? .month : .year, value: 1, to: periodStart)!
    }
    var prevPeriodStart: Date {
        Calendar.current.date(byAdding: mode == .month ? .month : .year, value: -1, to: periodStart)!
    }
    var prevPeriodEnd: Date { periodStart }
    var yearStart: Date {
        Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))!
    }

    static func current() -> DashboardPeriod {
        let cal = Calendar.current
        let now = Date()
        return DashboardPeriod(year: cal.component(.year, from: now), month: cal.component(.month, from: now), mode: .month)
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class DashboardViewModel {
    var isLoading = false
    var error: String?
    var period: DashboardPeriod = .current()

    // KPIs
    var thisMonthTotal: Double = 0       // selected-period total (a month, or a whole year)
    var lastMonthTotal: Double = 0       // previous-period total
    var thisYearTotal: Double = 0        // calendar year containing the selection — always a full year
    var cardOutstanding: Double = 0
    var cardOutstandingPrev: Double = 0
    var cardUnbilled: Double = 0
    var cardUnbilledPrev: Double = 0
    var savedThisPeriod: Double = 0
    var savedPrevPeriod: Double = 0
    var savedThisYear: Double = 0
    var incomeThisPeriod: Double = 0
    var savingsRatePct: Int?

    // Charts
    var savingsTrend: [MonthBar] = []
    var savingsSeries: [SavingsSeries] = []
    var savingsRateTrend: [RatePoint] = []
    var monthlyTrend: [MonthBar] = []
    var thisMonthByCategory: [CategoryBar] = []
    var byCategory: [CategoryBar] = []
    var byMethod: [MethodBar] = []
    var topMerchants: [TopMerchant] = []
    var spendPace: [PacePoint] = []
    var byWeekday: [WeekdayBar] = []
    var categoryDeltas: [CategoryDelta] = []
    var recentExpenses: [Expense] = []
    var dailyData: [HouseholdDailyPoint] = []

    private let expenseService: ExpenseService
    private let accountService: PaymentAccountService
    private let categoryService: CategoryService
    private let incomeService: IncomeService

    init(auth: AuthState) {
        expenseService = ExpenseService(auth: auth)
        accountService = PaymentAccountService(auth: auth)
        categoryService = CategoryService(auth: auth)
        incomeService = IncomeService(auth: auth)
    }

    func load(period: DashboardPeriod) async {
        self.period = period
        isLoading = true
        error = nil
        do {
            let cal = Calendar.current
            let now = Date()
            let isMonthMode = period.mode == .month

            let periodStart = period.periodStart
            let periodEnd = period.periodEnd
            let prevPeriodStart = period.prevPeriodStart
            let prevPeriodEnd = period.prevPeriodEnd
            let yearStart = period.yearStart

            let trendStart = isMonthMode ? cal.date(byAdding: .month, value: -5, to: periodStart)! : yearStart
            let trendMonthCount = isMonthMode ? 6 : 12

            let fetchFrom = min(trendStart, prevPeriodStart, yearStart)

            var windowFilters = ExpenseFilters()
            windowFilters.status = .submitted
            windowFilters.from = fetchFrom
            windowFilters.to = periodEnd
            windowFilters.pageSize = 2000

            async let windowResult  = expenseService.getExpenses(filters: windowFilters)
            async let cats          = categoryService.getCategories()
            async let accountStats  = accountService.getStats()

            let (window, allCategories, stats) = try await (windowResult, cats, accountStats)

            // Categories flagged "not an expense" (transfers, card payments) drop out of every
            // spending figure below. Savings/investment categories are matched by name and
            // reported as their own figure rather than counted as spend. Card KPIs further down
            // come from payment-account stats rather than categories, so those still include both.
            let excludedIds = allCategories.excludedCategoryIds()
            let savingsIds = allCategories.savingsCategoryIds()
            let spendExcludedIds = excludedIds.union(savingsIds)
            let categories = allCategories.pruneExcluded()
            let items = window.items.filter { $0.categoryId == nil || !spendExcludedIds.contains($0.categoryId!) }
            let savingsItems = window.items.filter { $0.categoryId != nil && savingsIds.contains($0.categoryId!) }

            let periodItems = items.filter { $0.transactionDate >= periodStart && $0.transactionDate < periodEnd }
            let prevPeriodItems = items.filter { $0.transactionDate >= prevPeriodStart && $0.transactionDate < prevPeriodEnd }
            let yearItems = items.filter { $0.transactionDate >= yearStart && $0.transactionDate < cal.date(byAdding: .year, value: 1, to: yearStart)! }

            thisMonthTotal = periodItems.map(\.amount).reduce(0, +)
            lastMonthTotal = prevPeriodItems.map(\.amount).reduce(0, +)
            thisYearTotal  = yearItems.map(\.amount).reduce(0, +)

            func savedInRange(_ start: Date, _ end: Date) -> Double {
                savingsItems.filter { $0.transactionDate >= start && $0.transactionDate < end }
                    .map(\.amount).reduce(0, +)
            }
            savedThisPeriod = savedInRange(periodStart, periodEnd)
            savedPrevPeriod = savedInRange(prevPeriodStart, prevPeriodEnd)
            savedThisYear = savedInRange(yearStart, cal.date(byAdding: .year, value: 1, to: yearStart)!)

            // Income — used only to derive the savings rate. Failures here must not blank the rest
            // of the dashboard, so a fetch error just leaves income at zero / rate at nil.
            let monthsBack = min(24, max(1, (cal.dateComponents([.month], from: trendStart, to: now).month ?? 0) + 1))
            let incomeSummary = (try? await incomeService.getSummary(months: monthsBack)) ?? []
            incomeThisPeriod = incomeSummary
                .filter {
                    let d = cal.date(from: DateComponents(year: $0.year, month: $0.month, day: 1))!
                    return d >= periodStart && d < periodEnd
                }
                .map(\.total).reduce(0, +)
            savingsRatePct = incomeThisPeriod > 0 ? Int((savedThisPeriod / incomeThisPeriod) * 100) : nil

            // Monthly trend — trailing 6 months ending at the selected month, or 12 months of the selected year.
            // Savings is folded into the same loop but kept on its own scale.
            let nowYear = cal.component(.year, from: now)
            let nowMonth = cal.component(.month, from: now)
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMM"
            let trendMonths: [Date] = (0..<trendMonthCount).map { cal.date(byAdding: .month, value: $0, to: trendStart)! }

            let trend: [MonthBar] = trendMonths.map { ym in
                let start = cal.dateInterval(of: .month, for: ym)!.start
                let end   = cal.dateInterval(of: .month, for: ym)!.end
                let total = items.filter { $0.transactionDate >= start && $0.transactionDate < end }
                    .map(\.amount).reduce(0, +)
                let comps = cal.dateComponents([.year, .month], from: start)
                let isCurrent = comps.year == nowYear && comps.month == nowMonth
                return MonthBar(label: monthFormatter.string(from: start), total: total, pct: 0, isCurrent: isCurrent)
            }
            let maxMonth = trend.map(\.total).max() ?? 1
            monthlyTrend = trend.map { b in
                MonthBar(label: b.label, total: b.total,
                         pct: maxMonth > 0 ? Int((b.total / maxMonth) * 100) : 0,
                         isCurrent: b.isCurrent)
            }

            let savingsTrendRaw: [MonthBar] = trendMonths.map { ym in
                let start = cal.dateInterval(of: .month, for: ym)!.start
                let end   = cal.dateInterval(of: .month, for: ym)!.end
                let total = savedInRange(start, end)
                let comps = cal.dateComponents([.year, .month], from: start)
                let isCurrent = comps.year == nowYear && comps.month == nowMonth
                return MonthBar(label: monthFormatter.string(from: start), total: total, pct: 0, isCurrent: isCurrent)
            }
            let maxSavingsMonth = savingsTrendRaw.map(\.total).max() ?? 1
            savingsTrend = savingsTrendRaw.map { b in
                MonthBar(label: b.label, total: b.total,
                         pct: maxSavingsMonth > 0 ? Int((b.total / maxSavingsMonth) * 100) : 0,
                         isCurrent: b.isCurrent)
            }

            // Split each trend month across the top-level savings buckets (Equity, Debt, …), which
            // is what the stacked chart plots. Money booked straight on a savings root, or in a
            // bucket past the group ceiling, falls into "Other" so the stack still sums to
            // savedThisPeriod above rather than quietly losing a slice.
            let groups = allCategories.savingsGroups()
            func totalIn(_ ids: Set<String>, _ start: Date, _ end: Date) -> Double {
                savingsItems.filter { $0.transactionDate >= start && $0.transactionDate < end && $0.categoryId != nil && ids.contains($0.categoryId!) }
                    .map(\.amount).reduce(0, +)
            }
            var series = groups.map { g -> SavingsSeries in
                let values = trendMonths.map { ym -> Double in
                    let start = cal.dateInterval(of: .month, for: ym)!.start
                    let end   = cal.dateInterval(of: .month, for: ym)!.end
                    return totalIn(g.ids, start, end)
                }
                return SavingsSeries(name: g.name, icon: g.icon, color: g.color, values: values)
            }
            let groupedIds = Set(groups.flatMap { $0.ids })
            let otherValues = trendMonths.map { ym -> Double in
                let start = cal.dateInterval(of: .month, for: ym)!.start
                let end   = cal.dateInterval(of: .month, for: ym)!.end
                return savingsItems.filter {
                    $0.transactionDate >= start && $0.transactionDate < end
                        && ($0.categoryId == nil || !groupedIds.contains($0.categoryId!))
                }.map(\.amount).reduce(0, +)
            }
            if otherValues.contains(where: { $0 > 0 }) {
                series.append(SavingsSeries(name: "Other", icon: nil, color: savingsOtherColor, values: otherValues))
            }
            savingsSeries = series.filter { s in s.values.contains { $0 > 0 } }

            // Saved as a share of income, over the same trend months. A month with no recorded
            // income has an unknown rate, not a zero one, so it stays nil and the line breaks.
            savingsRateTrend = trendMonths.enumerated().map { i, ym in
                let comps = cal.dateComponents([.year, .month], from: ym)
                let earned = incomeSummary
                    .filter { $0.year == comps.year && $0.month == comps.month }
                    .map(\.total).reduce(0, +)
                let isCurrent = comps.year == nowYear && comps.month == nowMonth
                return RatePoint(
                    label: monthFormatter.string(from: ym),
                    rate: earned > 0 ? Int((savingsTrendRaw[i].total / earned) * 100) : nil,
                    isCurrent: isCurrent
                )
            }

            // Category bucket map (walk hierarchy, tracking both root and immediate-sub identity)
            let bucketMap = buildBucketMap(categories)

            func toCategoryBars(_ list: [Expense]) -> [CategoryBar] {
                var totals: [String: (Double, String?)] = [:]
                for e in list {
                    let info = bucketMap[e.categoryId]
                    let name = info?.rootName ?? "Uncategorized"
                    let icon = info?.rootIcon
                    let cur = totals[name] ?? (0, icon)
                    totals[name] = (cur.0 + e.amount, icon)
                }
                let grand = totals.values.map(\.0).reduce(0, +)
                return totals.sorted { $0.value.0 > $1.value.0 }
                    .enumerated()
                    .map { idx, kv in
                        CategoryBar(name: kv.key, icon: kv.value.1, total: kv.value.0,
                                    pct: grand > 0 ? Int((kv.value.0 / grand) * 100) : 0,
                                    color: dashboardColors[idx % dashboardColors.count])
                    }
            }

            let periodCats = toCategoryBars(periodItems)
            thisMonthByCategory = periodCats
            byCategory          = toCategoryTree(periodItems, categories)

            // Top merchants (selected period)
            var merchantMap: [String: (Double, Int)] = [:]
            for e in periodItems {
                let cur = merchantMap[e.merchant] ?? (0, 0)
                merchantMap[e.merchant] = (cur.0 + e.amount, cur.1 + 1)
            }
            topMerchants = merchantMap.sorted { $0.value.0 > $1.value.0 }
                .prefix(6).map { TopMerchant(name: $0.key, total: $0.value.0, count: $0.value.1) }

            // By method (selected period)
            var methodMap: [String: Double] = [:]
            for e in periodItems { methodMap[e.paymentMethod.rawValue, default: 0] += e.amount }
            let methodTotal = methodMap.values.reduce(0, +)
            byMethod = methodMap.sorted { $0.value > $1.value }.map { m, total in
                MethodBar(method: m, total: total,
                          pct: methodTotal > 0 ? Float(total / methodTotal) : 0,
                          color: methodColors[m] ?? "#94a3b8")
            }

            // Spend pace — cumulative running total per day-of-month, selected vs previous period.
            // Only meaningful at day granularity, so Year mode leaves this empty (card is hidden).
            func pacePoints(_ list: [Expense], tag: String, upTo lastDay: Int) -> [PacePoint] {
                var byDay: [Int: Double] = [:]
                for e in list {
                    let d = cal.component(.day, from: e.transactionDate)
                    byDay[d, default: 0] += e.amount
                }
                guard lastDay > 0 else { return [] }
                var running = 0.0
                return (1...lastDay).map { d in
                    running += byDay[d] ?? 0
                    return PacePoint(day: d, amount: running, period: tag)
                }
            }
            if isMonthMode {
                let periodDaysInMonth = cal.range(of: .day, in: .month, for: periodStart)?.count ?? 30
                let lastDayThisPeriod = period.isAtPresent ? cal.component(.day, from: now) : periodDaysInMonth
                let daysInPrevMonth = cal.range(of: .day, in: .month, for: prevPeriodStart)?.count ?? 30
                spendPace = pacePoints(periodItems, tag: "This Month", upTo: lastDayThisPeriod)
                          + pacePoints(prevPeriodItems, tag: "Last Month", upTo: daysInPrevMonth)
            } else {
                spendPace = []
            }

            // Spending by weekday (selected period), Mon…Sun, zero-filled
            let shortDays = DateFormatter().shortWeekdaySymbols ?? ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            var weekdayTotals: [Int: Double] = [:]   // 1 = Sunday … 7 = Saturday
            for e in periodItems {
                let wd = cal.component(.weekday, from: e.transactionDate)
                weekdayTotals[wd, default: 0] += e.amount
            }
            let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]  // Mon-first
            byWeekday = weekdayOrder.map { wd in
                WeekdayBar(label: shortDays[wd - 1], total: weekdayTotals[wd] ?? 0)
            }

            // Category — selected period vs previous period (top 6 by combined total)
            func categoryTotals(_ list: [Expense]) -> [String: (Double, String?)] {
                var totals: [String: (Double, String?)] = [:]
                for e in list {
                    let info = bucketMap[e.categoryId]
                    let name = info?.rootName ?? "Uncategorized"
                    let icon = info?.rootIcon
                    let cur = totals[name] ?? (0, icon)
                    totals[name] = (cur.0 + e.amount, icon)
                }
                return totals
            }
            let thisCat = categoryTotals(periodItems)
            let lastCat = categoryTotals(prevPeriodItems)
            categoryDeltas = Set(thisCat.keys).union(lastCat.keys)
                .map { name in
                    CategoryDelta(name: name,
                                  icon: thisCat[name]?.1 ?? lastCat[name]?.1,
                                  thisMonth: thisCat[name]?.0 ?? 0,
                                  lastMonth: lastCat[name]?.0 ?? 0)
                }
                .sorted { ($0.thisMonth + $0.lastMonth) > ($1.thisMonth + $1.lastMonth) }
                .prefix(6)
                .map { $0 }

            // Card stats — pinned to "current", independent of period
            let statsById = Dictionary(uniqueKeysWithValues: stats.map { ($0.accountId, $0) })
            let accounts = try await accountService.getAccounts()
            let cardAccounts = accounts.filter { $0.accountType.isCredit }
            cardOutstanding     = cardAccounts.compactMap { statsById[$0.id]?.lastBilledAmount }.reduce(0, +)
            cardOutstandingPrev = cardAccounts.compactMap { statsById[$0.id]?.lastBilledAmountPrev }.reduce(0, +)
            cardUnbilled        = cardAccounts.compactMap { statsById[$0.id]?.unbilledAmount }.reduce(0, +)
            cardUnbilledPrev    = cardAccounts.compactMap { statsById[$0.id]?.unbilledAmountPrev }.reduce(0, +)

            recentExpenses = periodItems.sorted { $0.transactionDate > $1.transactionDate }.prefix(6).map { $0 }

            // Daily spend for the selected month — hidden (empty) in Year mode
            dailyData = isMonthMode ? computeDaily(periodItems, year: period.year, month: period.month) : []

        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func computeDaily(_ items: [Expense], year: Int, month: Int) -> [HouseholdDailyPoint] {
        let cal = Calendar.current
        let len = cal.range(of: .day, in: .month, for: cal.date(from: DateComponents(year: year, month: month, day: 1))!)?.count ?? 30
        var byDay = [Double](repeating: 0, count: len + 1)
        for e in items {
            let comps = cal.dateComponents([.year, .month, .day], from: e.transactionDate)
            if comps.year == year && comps.month == month, let day = comps.day {
                byDay[day] += e.amount
            }
        }
        return (1...len).map { HouseholdDailyPoint(day: $0, total: byDay[$0]) }
    }

    private struct BucketInfo {
        let rootName: String
        let rootIcon: String?
    }

    private func buildBucketMap(_ cats: [Category]) -> [String?: BucketInfo] {
        var map: [String?: BucketInfo] = [:]
        func walk(_ cat: Category, rootName: String, rootIcon: String?) {
            map[cat.id] = BucketInfo(rootName: rootName, rootIcon: rootIcon)
            for child in cat.children { walk(child, rootName: rootName, rootIcon: rootIcon) }
        }
        for cat in cats { walk(cat, rootName: cat.name, rootIcon: cat.icon) }
        return map
    }

    /// Full category tree for the "By Categories" card — every category node (any depth) becomes
    /// an expandable `CategoryBar`. Expenses booked directly on a non-leaf category surface as a
    /// child row named after that category itself. All percentages are share of grand total, so a
    /// parent's children always sum to the parent's own percentage.
    private func toCategoryTree(_ items: [Expense], _ cats: [Category]) -> [CategoryBar] {
        var directAmounts: [String: Double] = [:]
        var uncategorizedTotal = 0.0
        for e in items {
            if let cid = e.categoryId {
                directAmounts[cid, default: 0] += e.amount
            } else {
                uncategorizedTotal += e.amount
            }
        }
        let grand = directAmounts.values.reduce(0, +) + uncategorizedTotal
        func pct(_ v: Double) -> Int { grand > 0 ? Int((v / grand) * 100) : 0 }

        func subtreeTotal(_ cat: Category) -> Double {
            (directAmounts[cat.id] ?? 0) + cat.children.map(subtreeTotal).reduce(0, +)
        }

        func buildNode(_ cat: Category, color: String) -> CategoryBar? {
            let direct = directAmounts[cat.id] ?? 0
            let childBars = cat.children.compactMap { buildNode($0, color: color) }
            let total = direct + childBars.map(\.total).reduce(0, +)
            guard total > 0 else { return nil }
            var children = childBars
            if direct > 0 {
                children.append(CategoryBar(name: cat.name, icon: cat.icon, total: direct,
                                             pct: pct(direct), color: color))
            }
            children.sort { $0.total > $1.total }
            return CategoryBar(name: cat.name, icon: cat.icon, total: total,
                                pct: pct(total), color: color, children: children)
        }

        struct RootEntry { let cat: Category?; let total: Double }
        let ranked = (cats.map { RootEntry(cat: $0, total: subtreeTotal($0)) } + [RootEntry(cat: nil, total: uncategorizedTotal)])
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }

        return ranked.enumerated().compactMap { idx, entry in
            let color = dashboardColors[idx % dashboardColors.count]
            guard let cat = entry.cat else {
                return CategoryBar(name: "Uncategorized", icon: nil, total: entry.total,
                                    pct: pct(entry.total), color: color)
            }
            return buildNode(cat, color: color)
        }
    }
}
