import Foundation

/// Builds the grounding text sent as the first user turn — plain prose the model reads, not JSON.
/// Mirrors Android's `ExpenseContextBuilder`: a wide window of Submitted expenses (widened several
/// months before the selected period for trend/recurring detection), summarized into the sections
/// below. The model still has live tool access on top of this for anything not covered here.
@MainActor
final class ExpenseContextBuilder {
    private static let historyMonths = 6
    private static let pageSize = 1000
    private static let maxPages = 5
    private static let maxSubcategories = 25
    private static let avgDaysPerMonth = 30.44
    /// Top-level buckets left out of analysis: settling a debt is money movement, not spend.
    /// Matches Android's `EXCLUDED_PARENT_CATEGORIES`.
    private static let excludedBucketNames: Set<String> = ["repayment", "repayments"]

    private let expenseService: ExpenseService
    private let categoryService: CategoryService
    private let incomeService: IncomeService
    private let tagService: TagService
    private let budgetService: BudgetService

    init(auth: AuthState) {
        expenseService = ExpenseService(auth: auth)
        categoryService = CategoryService(auth: auth)
        incomeService = IncomeService(auth: auth)
        tagService = TagService(auth: auth)
        budgetService = BudgetService(auth: auth)
    }

    func build(period: DashboardPeriod) async -> String {
        let cal = Calendar.current
        let periodStart = period.periodStart
        let periodEnd = period.periodEnd
        let historyStart = cal.date(byAdding: .month, value: -Self.historyMonths, to: periodStart) ?? periodStart

        var filters = ExpenseFilters()
        filters.status = .submitted
        filters.from = historyStart
        filters.to = periodEnd
        filters.pageSize = Self.pageSize

        var all: [Expense] = []
        var apiTotal = 0
        var fetchFailed = false
        for page in 1...Self.maxPages {
            filters.page = page
            guard let result = try? await expenseService.getExpenses(filters: filters) else {
                fetchFailed = true
                break
            }
            apiTotal = result.total
            all += result.items
            if result.items.isEmpty || all.count >= result.total { break }
        }
        // Whether the window was cut short, either by the page ceiling or by a failed request. The
        // model has to be told, or it reports a partial total as the whole truth.
        let truncated = fetchFailed || all.count < apiTotal

        let allCategories = (try? await categoryService.getCategories()) ?? []
        let excludedIds = allCategories.excludedCategoryIds()
        let savingsIds = allCategories.savingsCategoryIds()
        let bucketMap = buildBucketMap(allCategories)
        // Money movement, savings contributions and debt settlement all left the account without
        // being spent. The first two are resolved by category flag/name; repayment is a root-bucket
        // name, matching Android's `EXCLUDED_PARENT_CATEGORIES` (ExpenseContextBuilder.kt).
        let nonSpendIds = excludedIds.union(savingsIds)
        func isSpend(_ e: Expense) -> Bool {
            if let id = e.categoryId, nonSpendIds.contains(id) { return false }
            guard let bucket = bucketMap[e.categoryId] else { return true }
            return !Self.excludedBucketNames.contains(bucket.trimmingCharacters(in: .whitespaces).lowercased())
        }
        let spendable = all.filter(isSpend)
        let periodItems = spendable.filter { $0.transactionDate >= periodStart && $0.transactionDate < periodEnd }
        // Reported on its own below rather than counted as spend — it left the account but was
        // never spent.
        let savedInPeriod = all
            .filter { $0.transactionDate >= periodStart && $0.transactionDate < periodEnd }
            .filter { $0.categoryId.map(savingsIds.contains) ?? false }
            .map(\.amount).reduce(0, +)

        // The summary returns trailing months ending at the current one, so ask for enough of them
        // to reach back to `periodStart` — a year period must compare its full spend against its
        // full income, not just the selected month's.
        let monthsBack = (cal.dateComponents([.month], from: periodStart, to: Date()).month ?? 0) + 1
        let incomeSummary = (try? await incomeService.getSummary(months: min(max(monthsBack, 1), 24))) ?? []
        let periodIncome = incomeSummary.filter { point in
            guard let start = cal.date(from: DateComponents(year: point.year, month: point.month, day: 1)) else { return false }
            return start >= periodStart && start < periodEnd
        }
        let tags = (try? await tagService.getTags()) ?? []

        // Normalisation: a period's headline total means little without knowing how long it ran.
        let clampedEnd = min(periodEnd, max(periodStart, Date()))
        let daysElapsed = max(1, (cal.dateComponents([.day], from: periodStart, to: clampedEnd).day ?? 0) + 1)
        let monthsElapsed = Double(daysElapsed) / Self.avgDaysPerMonth
        let isMultiMonth = monthsElapsed > 1.5

        var lines: [String] = []
        lines.append("Period: \(period.label) (\(periodStart.apiDateString) → \(clampedEnd.apiDateString), \(daysElapsed) days elapsed ≈ \(String(format: "%.1f", monthsElapsed)) months)")
        if truncated {
            lines.append("Note: showing \(all.count) of \(max(apiTotal, all.count)) transactions in the fetch window — totals below cover only those.")
        }
        lines.append("Currency: INR")
        lines.append("")

        let total = periodItems.map(\.amount).reduce(0, +)
        lines.append("Total spend this period: \(total.formattedINR)")
        lines.append("Transactions: \(periodItems.count)")
        if monthsElapsed > 0.03 {
            lines.append("Per month: \((total / monthsElapsed).formattedINR)   |   Per day: \((total / Double(daysElapsed)).formattedINR)")
        }
        if savedInPeriod > 0 {
            lines.append("Saved into savings & investment categories: \(savedInPeriod.formattedINR) (not counted in spend above)")
        }
        if !periodIncome.isEmpty {
            let incomeTotal = periodIncome.map(\.total).reduce(0, +)
            let fixedTotal = periodIncome.map(\.fixed).reduce(0, +)
            let variableTotal = periodIncome.map(\.variable).reduce(0, +)
            lines.append("Income this period: \(incomeTotal.formattedINR) (fixed \(fixedTotal.formattedINR), variable \(variableTotal.formattedINR))")
            // Per-source, merged across every month the period covers — "is my salary the whole
            // picture?" needs the breakdown, not just the total.
            var bySource: [String: (kind: IncomeKind, amount: Double)] = [:]
            for point in periodIncome {
                for source in point.bySource {
                    bySource[source.name, default: (source.kind, 0)].amount += source.amount
                }
            }
            for (name, agg) in bySource.sorted(by: { $0.value.amount > $1.value.amount }) {
                lines.append("  - \(name) (\(agg.kind.rawValue.lowercased())): \(agg.amount.formattedINR)")
            }
            if incomeTotal > 0 {
                lines.append("Unspent (income − spend): \(Int((max(0, incomeTotal - total) / incomeTotal) * 100))% of income")
                if savedInPeriod > 0 {
                    lines.append("Measured savings rate: \(Int((savedInPeriod / incomeTotal) * 100))% of income (booked to savings/investment categories)")
                }
            }
        }
        lines.append("")

        // Category hierarchy, so the model can talk about subcategories that saw no spend this
        // period and knows which parent a name belongs under.
        let hierarchy = allCategories
            .filter { cat in
                !cat.children.isEmpty
                    && !Self.excludedBucketNames.contains(cat.name.trimmingCharacters(in: .whitespaces).lowercased())
                    && cat.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(savingsCategoryName) != .orderedSame
            }
            .map { root -> String in
                let subs = root.children.map { child in
                    child.children.isEmpty
                        ? child.name
                        : "\(child.name) (\(child.children.map(\.name).joined(separator: ", ")))"
                }
                return "- \(root.name): \(subs.joined(separator: ", "))"
            }
        if !hierarchy.isEmpty {
            lines.append("Category hierarchy (parent: subcategories):")
            lines += hierarchy
            lines.append("")
        }

        // By category (root bucket)
        let leafName = leafNameLookup(allCategories)
        var byCategory: [String: (amount: Double, count: Int)] = [:]
        for e in periodItems {
            let name = bucketMap[e.categoryId] ?? "Uncategorized"
            let current = byCategory[name] ?? (0, 0)
            byCategory[name] = (current.amount + e.amount, current.count + 1)
        }
        if !byCategory.isEmpty {
            lines.append("Spend by category group (amount, count):")
            for (name, agg) in byCategory.sorted(by: { $0.value.amount > $1.value.amount }).prefix(15) {
                let perMonth = isMultiMonth ? " · ~\((agg.amount / monthsElapsed).formattedINR)/mo" : ""
                lines.append("- \(name): \(agg.amount.formattedINR) (\(agg.count))\(perMonth)")
            }
            lines.append("")
        }

        // By subcategory — the level the user actually books to, and the one a recommendation has
        // to name to be actionable.
        var bySub: [String: (amount: Double, count: Int)] = [:]
        for e in periodItems {
            let leaf = e.categoryName?.isEmpty == false ? e.categoryName! : (leafName[e.categoryId ?? ""] ?? "Uncategorized")
            let parent = bucketMap[e.categoryId] ?? leaf
            let label = parent == leaf ? leaf : "\(leaf) (under \(parent))"
            let current = bySub[label] ?? (0, 0)
            bySub[label] = (current.amount + e.amount, current.count + 1)
        }
        if !bySub.isEmpty {
            let ranked = bySub.sorted { $0.value.amount > $1.value.amount }
            lines.append("Spend by subcategory (amount, count):")
            for (label, agg) in ranked.prefix(Self.maxSubcategories) {
                lines.append("- \(label): \(agg.amount.formattedINR) (\(agg.count))")
            }
            let rest = ranked.dropFirst(Self.maxSubcategories)
            if !rest.isEmpty {
                let restAmount = rest.map(\.value.amount).reduce(0, +)
                let restCount = rest.map(\.value.count).reduce(0, +)
                lines.append("- Other: \(restAmount.formattedINR) (\(restCount))")
            }
            lines.append("")
        }

        // By payment method
        var byMethod: [String: Double] = [:]
        for e in periodItems { byMethod[e.paymentMethod.displayName, default: 0] += e.amount }
        if !byMethod.isEmpty {
            lines.append("By payment method:")
            for (name, amt) in byMethod.sorted(by: { $0.value > $1.value }) {
                lines.append("- \(name): \(amt.formattedINR)")
            }
            lines.append("")
        }

        // Top merchants
        var byMerchant: [String: Double] = [:]
        for e in periodItems { byMerchant[e.merchant, default: 0] += e.amount }
        if !byMerchant.isEmpty {
            lines.append("Top merchants this period:")
            for (name, amt) in byMerchant.sorted(by: { $0.value > $1.value }).prefix(10) {
                lines.append("- \(name): \(amt.formattedINR)")
            }
            lines.append("")
        }

        // By tag (own + inherited, overlapping — an expense may count under several tags)
        if !tags.isEmpty {
            var byTag: [String: Double] = [:]
            var untagged = 0.0
            for e in periodItems {
                let names = Set(e.allTags.map(\.name))
                if names.isEmpty { untagged += e.amount }
                for name in names { byTag[name, default: 0] += e.amount }
            }
            if !byTag.isEmpty || untagged > 0 {
                lines.append("By tag (a transaction may carry more than one):")
                for (name, amt) in byTag.sorted(by: { $0.value > $1.value }).prefix(15) {
                    lines.append("- \(name): \(amt.formattedINR)")
                }
                if untagged > 0 { lines.append("- (untagged): \(untagged.formattedINR)") }
                lines.append("")
            }
        }

        // Month-over-month trend. Each row carries its change against the prior month and whether it
        // falls inside the selected period, so history isn't mistaken for the period being asked about.
        var trend: [(label: String, amount: Double, count: Int, inPeriod: Bool)] = []
        let monthFormatter = DateFormatter(); monthFormatter.dateFormat = "MMM yyyy"
        for i in stride(from: Self.historyMonths, through: 0, by: -1) {
            guard let ym = cal.date(byAdding: .month, value: -i, to: periodStart),
                  let interval = cal.dateInterval(of: .month, for: ym) else { continue }
            let inMonth = spendable.filter { $0.transactionDate >= interval.start && $0.transactionDate < interval.end }
            trend.append((monthFormatter.string(from: interval.start),
                          inMonth.map(\.amount).reduce(0, +),
                          inMonth.count,
                          interval.start >= periodStart && interval.start < periodEnd))
        }
        if !trend.isEmpty {
            lines.append("Month-over-month trend:")
            var prev: Double?
            for row in trend {
                var change = ""
                if let prev, prev > 0 {
                    let pct = Int(((row.amount - prev) / prev * 100).rounded())
                    change = " (\(pct >= 0 ? "+" : "")\(pct)% vs prior month)"
                }
                prev = row.amount
                lines.append("- \(row.label) (\(row.inPeriod ? "this period" : "history")): \(row.amount.formattedINR) (\(row.count))\(change)")
            }
            lines.append("")
        }

        // Likely recurring charges — same merchant, amounts within 15% of the mean, across
        // at least 3 distinct months in the widened window.
        let recurring = detectRecurring(spendable)
        if !recurring.isEmpty {
            lines.append("Likely recurring charges (detected, not user-confirmed):")
            for r in recurring.prefix(10) {
                lines.append("- \(r.merchant): ~\(r.avgAmount.formattedINR)/month, seen in \(r.monthCount) months")
            }
            lines.append("")
        }

        // Budget vs actual — the single most-asked question of this assistant, and previously
        // absent, forcing a tool round-trip for something the snapshot should already answer.
        let budgetLines = await buildBudgetSection(year: period.year, month: period.month)
        if !budgetLines.isEmpty {
            lines.append("Budget vs actual (\(period.label)):")
            lines += budgetLines
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Flattened `budget / actual / variance` per budget for the selected month. Best-effort: a
    /// failure here drops the section rather than failing the whole context.
    private func buildBudgetSection(year: Int, month: Int) async -> [String] {
        guard let budgets = try? await budgetService.getBudgets(year: year, month: month) else { return [] }
        var lines: [String] = []
        func walk(_ b: Budget) {
            // A month before the budget's first cycle had nothing to spend against.
            if !b.isBeforeStart {
                let label = b.categoryName ?? b.name
                let variance = b.effectiveAmount - b.spent
                let status = b.spent > b.effectiveAmount ? "over" : "on track"
                lines.append("- \(label): budget \(b.effectiveAmount.formattedINR), actual \(b.spent.formattedINR), variance \(variance >= 0 ? "+" : "")\(variance.formattedINR) (\(status))")
            }
            for child in b.children { walk(child) }
        }
        for b in budgets { walk(b) }
        return lines
    }

    /// categoryId → that category's own name, for resolving the leaf an expense was booked to when
    /// the server didn't denormalize it onto the row.
    private func leafNameLookup(_ cats: [Category]) -> [String: String] {
        var map: [String: String] = [:]
        func walk(_ c: Category) {
            map[c.id] = c.name
            for child in c.children { walk(child) }
        }
        for c in cats { walk(c) }
        return map
    }

    private func buildBucketMap(_ cats: [Category]) -> [String?: String] {
        var map: [String?: String] = [:]
        func walk(_ c: Category, rootName: String) {
            map[c.id] = rootName
            for child in c.children { walk(child, rootName: rootName) }
        }
        for c in cats { walk(c, rootName: c.name) }
        return map
    }

    private struct RecurringCandidate {
        let merchant: String
        let avgAmount: Double
        let monthCount: Int
        let totalAmount: Double
    }

    private func detectRecurring(_ items: [Expense]) -> [RecurringCandidate] {
        let cal = Calendar.current
        func normalize(_ merchant: String) -> String {
            merchant.lowercased().replacingOccurrences(of: "[0-9]+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        var byMerchant: [String: [(month: String, amount: Double, raw: String)]] = [:]
        for e in items {
            let comps = cal.dateComponents([.year, .month], from: e.transactionDate)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            byMerchant[normalize(e.merchant), default: []].append((key, e.amount, e.merchant))
        }
        var candidates: [RecurringCandidate] = []
        for (merchant, occurrences) in byMerchant where !merchant.isEmpty {
            let distinctMonths = Set(occurrences.map(\.month))
            guard distinctMonths.count >= 3 else { continue }
            let amounts = occurrences.map(\.amount)
            let mean = amounts.reduce(0, +) / Double(amounts.count)
            guard mean > 0, amounts.allSatisfy({ abs($0 - mean) / mean <= 0.15 }) else { continue }
            // Report the merchant as it actually appears, not the normalized grouping key —
            // "netflix" is what the key looks like after lowercasing and stripping digits, and
            // showing that back reads as a typo. Pick the spelling seen most often.
            var spellingCounts: [String: Int] = [:]
            for o in occurrences { spellingCounts[o.raw, default: 0] += 1 }
            let displayName = spellingCounts.max { $0.value < $1.value }?.key ?? merchant
            candidates.append(RecurringCandidate(merchant: displayName, avgAmount: mean,
                                                 monthCount: distinctMonths.count,
                                                 totalAmount: amounts.reduce(0, +)))
        }
        // Ranked by total spend: the biggest drain is the one worth cutting, not the longest-running.
        return candidates.sorted { $0.totalAmount > $1.totalAmount }
    }
}
