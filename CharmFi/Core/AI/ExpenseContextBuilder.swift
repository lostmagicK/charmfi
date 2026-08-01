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

    private let expenseService: ExpenseService
    private let categoryService: CategoryService
    private let incomeService: IncomeService
    private let tagService: TagService

    init(auth: AuthState) {
        expenseService = ExpenseService(auth: auth)
        categoryService = CategoryService(auth: auth)
        incomeService = IncomeService(auth: auth)
        tagService = TagService(auth: auth)
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
        for page in 1...Self.maxPages {
            filters.page = page
            guard let result = try? await expenseService.getExpenses(filters: filters) else { break }
            all += result.items
            if result.items.count < Self.pageSize { break }
        }

        let allCategories = (try? await categoryService.getCategories()) ?? []
        let excludedIds = allCategories.excludedCategoryIds()
        let savingsIds = allCategories.savingsCategoryIds()
        let spendable = all.filter { $0.categoryId == nil || !(excludedIds.union(savingsIds).contains($0.categoryId!)) }
        let periodItems = spendable.filter { $0.transactionDate >= periodStart && $0.transactionDate < periodEnd }

        let incomeSummary = (try? await incomeService.getSummary(months: Self.historyMonths + 1)) ?? []
        let periodIncome = incomeSummary.first { $0.year == period.year && $0.month == period.month }
        let tags = (try? await tagService.getTags()) ?? []

        var lines: [String] = []
        lines.append("Period: \(period.label)")
        lines.append("Currency: INR")
        lines.append("")

        let total = periodItems.map(\.amount).reduce(0, +)
        lines.append("Total spend this period: \(total.formattedINR)")
        if let inc = periodIncome {
            lines.append("Income this period: \(inc.total.formattedINR) (fixed \(inc.fixed.formattedINR), variable \(inc.variable.formattedINR))")
            let savingsRate = inc.total > 0 ? Int((max(0, inc.total - total) / inc.total) * 100) : nil
            if let savingsRate { lines.append("Approx. savings rate: \(savingsRate)%") }
        }
        lines.append("")

        // By category (root bucket)
        let bucketMap = buildBucketMap(allCategories)
        var byCategory: [String: Double] = [:]
        for e in periodItems {
            let name = bucketMap[e.categoryId] ?? "Uncategorized"
            byCategory[name, default: 0] += e.amount
        }
        if !byCategory.isEmpty {
            lines.append("By category:")
            for (name, amt) in byCategory.sorted(by: { $0.value > $1.value }).prefix(15) {
                lines.append("- \(name): \(amt.formattedINR)")
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

        // Month-over-month trend
        var trend: [(String, Double)] = []
        for i in stride(from: Self.historyMonths, through: 0, by: -1) {
            guard let ym = cal.date(byAdding: .month, value: -i, to: periodStart),
                  let interval = cal.dateInterval(of: .month, for: ym) else { continue }
            let monthTotal = spendable.filter { $0.transactionDate >= interval.start && $0.transactionDate < interval.end }
                .map(\.amount).reduce(0, +)
            let formatter = DateFormatter(); formatter.dateFormat = "MMM yyyy"
            trend.append((formatter.string(from: interval.start), monthTotal))
        }
        if !trend.isEmpty {
            lines.append("Monthly trend (oldest to newest):")
            for (label, amt) in trend { lines.append("- \(label): \(amt.formattedINR)") }
            lines.append("")
        }

        // Likely recurring charges — same merchant, amounts within 15% of the mean, across
        // at least 3 distinct months in the widened window.
        let recurring = detectRecurring(spendable)
        if !recurring.isEmpty {
            lines.append("Likely recurring charges:")
            for r in recurring.prefix(10) {
                lines.append("- \(r.merchant): ~\(r.avgAmount.formattedINR)/mo, seen \(r.monthCount) months")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
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

    private struct RecurringCandidate { let merchant: String; let avgAmount: Double; let monthCount: Int }

    private func detectRecurring(_ items: [Expense]) -> [RecurringCandidate] {
        let cal = Calendar.current
        func normalize(_ merchant: String) -> String {
            merchant.lowercased().replacingOccurrences(of: "[0-9]+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        var byMerchant: [String: [(month: String, amount: Double)]] = [:]
        for e in items {
            let comps = cal.dateComponents([.year, .month], from: e.transactionDate)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            byMerchant[normalize(e.merchant), default: []].append((key, e.amount))
        }
        var candidates: [RecurringCandidate] = []
        for (merchant, occurrences) in byMerchant where !merchant.isEmpty {
            let distinctMonths = Set(occurrences.map(\.month))
            guard distinctMonths.count >= 3 else { continue }
            let amounts = occurrences.map(\.amount)
            let mean = amounts.reduce(0, +) / Double(amounts.count)
            guard mean > 0, amounts.allSatisfy({ abs($0 - mean) / mean <= 0.15 }) else { continue }
            candidates.append(RecurringCandidate(merchant: merchant, avgAmount: mean, monthCount: distinctMonths.count))
        }
        return candidates.sorted { $0.monthCount > $1.monthCount }
    }
}
