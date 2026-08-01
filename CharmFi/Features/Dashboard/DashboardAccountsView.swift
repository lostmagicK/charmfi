import SwiftUI
import Charts

/// One payment account's spend for the selected page-level period, used by the "Spend by Account" donut.
struct AccountSpend: Identifiable {
    var id: String { accountId }
    let accountId: String
    let accountName: String
    let total: Double
    let pct: Int
    let color: String
}

/// One (account, month) data point for the trailing 6-month spending-trend line chart.
struct AccountTrendPoint: Identifiable {
    var id: String { "\(accountId)-\(monthIndex)" }
    let accountId: String
    let accountName: String
    let monthIndex: Int
    let total: Double
    let color: String
}

/// One bar in the "Card Cycles" this-vs-last comparison chart.
struct CardCycleBar: Identifiable {
    let id = UUID()
    let card: String
    let phase: String   // "This cycle" | "Last cycle"
    let amount: Double
}

struct DashboardAccountsView: View {
    let period: DashboardPeriod
    @Environment(AuthState.self) private var authState
    @State private var accounts: [PaymentAccount] = []
    @State private var statsById: [String: AccountStats] = [:]
    @State private var byAccountSpend: [AccountSpend] = []
    @State private var spendTrend: [AccountTrendPoint] = []
    @State private var trendMonthLabels: [String] = []
    @State private var isLoading = false

    private var service: PaymentAccountService { PaymentAccountService(auth: authState) }
    private var expenseService: ExpenseService { ExpenseService(auth: authState) }

    private var cards:   [PaymentAccount] { accounts.filter { $0.accountType.isCard } }
    private var wallets: [PaymentAccount] { accounts.filter { !$0.accountType.isCard } }

    // Summary KPIs
    private var cardOutstanding: Double { cards.compactMap { statsById[$0.id]?.lastBilledAmount }.reduce(0, +) }
    private var cardLastMonth:   Double { cards.compactMap { statsById[$0.id]?.lastBilledAmountPrev }.reduce(0, +) }
    private var unbilled:        Double { cards.compactMap { statsById[$0.id]?.unbilledAmount }.reduce(0, +) }
    private var unbilledPrev:    Double { cards.compactMap { statsById[$0.id]?.unbilledAmountPrev }.reduce(0, +) }
    private var walletMonth:     Double { wallets.compactMap { statsById[$0.id]?.thisMonthSpend }.reduce(0, +) }
    private var walletLastMonth: Double { wallets.compactMap { statsById[$0.id]?.prevMonthSpend }.reduce(0, +) }

    // "Card Cycles" — this cycle (unbilled) vs last cycle (last billed), per card
    private var cycleCards: [PaymentAccount] {
        cards.filter { c in
            let s = statsById[c.id]
            return (s?.unbilledAmount ?? 0) > 0 || (s?.lastBilledAmount ?? 0) > 0
        }
    }
    private var cardCycleBars: [CardCycleBar] {
        cycleCards.flatMap { c -> [CardCycleBar] in
            let s = statsById[c.id]
            return [
                CardCycleBar(card: c.name, phase: "This cycle", amount: s?.unbilledAmount ?? 0),
                CardCycleBar(card: c.name, phase: "Last cycle", amount: s?.lastBilledAmount ?? 0)
            ]
        }
    }
    // Distinct trend accounts (name → color), preserving series order for the chart scale
    private var trendAccounts: [(name: String, color: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for p in spendTrend where !seen.contains(p.accountName) {
            seen.insert(p.accountName)
            out.append((p.accountName, p.color))
        }
        return out
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if accounts.isEmpty {
                ContentUnavailableView("No Payment Accounts", systemImage: "creditcard")
            } else {
                accountsList
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: period) { _, newPeriod in
            Task {
                await loadAccountSpend(for: newPeriod)
                await loadSpendTrend(for: newPeriod)
            }
        }
    }

    private var accountsList: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: []) {
                // ── Summary KPI row — pinned to "current" regardless of the page nav; these
                // are billing-cycle/current-balance figures, not sums over an arbitrary window.
                Text("CURRENT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: 8) {
                    accKpi("CARD OUTSTANDING", value: cardOutstanding.formattedINR,
                           pct: pct(cardOutstanding, cardLastMonth),
                           sub: "vs last cycle \(cardLastMonth.shortINR)")
                    accKpi("UNBILLED", value: unbilled.formattedINR,
                           pct: pct(unbilled, unbilledPrev),
                           sub: "vs prev \(unbilledPrev.shortINR)")
                    accKpi("ACCOUNTS & WALLETS", value: walletMonth.formattedINR,
                           pct: pct(walletMonth, walletLastMonth),
                           sub: "vs last mo \(walletLastMonth.shortINR)")
                }
                .fixedSize(horizontal: false, vertical: true)

                // ── Spend by Account — the one chart that responds to the page nav ───
                if !byAccountSpend.isEmpty {
                    spendByAccountCard
                }

                // ── Card Cycles — this cycle vs last cycle ───────────────────
                if !cardCycleBars.isEmpty {
                    cardCyclesCard
                }

                // ── Spending Trend — trailing 6 months, one line per account ─
                if !spendTrend.isEmpty {
                    spendTrendCard
                }

                // ── Cards ────────────────────────────────────────────────────
                if !cards.isEmpty {
                    sectionHeader(icon: "creditcard", title: "CARDS")
                    AdaptiveGrid(minColumnWidth: 360, spacing: 12) {
                        ForEach(cards) { account in
                            AccountDetailCard(account: account,
                                              stat: statsById[account.id],
                                              isCard: true)
                        }
                    }
                }

                // ── Accounts & Wallets ───────────────────────────────────────
                if !wallets.isEmpty {
                    sectionHeader(icon: "building.columns", title: "ACCOUNTS & WALLETS")
                    AdaptiveGrid(minColumnWidth: 360, spacing: 12) {
                        ForEach(wallets) { account in
                            AccountDetailCard(account: account,
                                              stat: statsById[account.id],
                                              isCard: false)
                        }
                    }
                }

                Spacer().frame(height: 20)
            }
            .padding(12)
        }
    }

    private var spendByAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Spend by Account").font(.subheadline.bold())
                Text(period.label).font(.caption).foregroundStyle(Color.accentColor)
            }
            HStack(alignment: .center, spacing: 16) {
                Chart(byAccountSpend) { bar in
                    SectorMark(
                        angle: .value("Total", bar.total),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color.fromHex(bar.color))
                    .cornerRadius(2)
                }
                .chartLegend(.hidden)
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(byAccountSpend) { bar in
                        HStack(spacing: 5) {
                            Circle().fill(Color.fromHex(bar.color)).frame(width: 8, height: 8)
                            Text(bar.accountName)
                                .font(.caption2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(bar.pct)%").font(.caption2).foregroundStyle(.secondary)
                            Text(bar.total.shortINR).font(.caption2).bold()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var cardCyclesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Card Cycles").font(.subheadline.bold())
                Text("this vs last cycle").font(.caption).foregroundStyle(Color.accentColor)
            }
            Chart(cardCycleBars) { bar in
                BarMark(
                    x: .value("Amount", bar.amount),
                    y: .value("Card", bar.card)
                )
                .foregroundStyle(by: .value("Phase", bar.phase))
                .position(by: .value("Phase", bar.phase))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale([
                "This cycle": Color.accentColor,
                "Last cycle": Color.secondary
            ])
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text(v.shortINR) } }
                }
            }
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: max(140, CGFloat(cycleCards.count) * 52))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var spendTrendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Spending Trend").font(.subheadline.bold())
                Text("last 6 months").font(.caption).foregroundStyle(Color.accentColor)
            }
            Chart(spendTrend) { point in
                LineMark(
                    x: .value("Month", point.monthIndex),
                    y: .value("Spend", point.total)
                )
                .foregroundStyle(by: .value("Account", point.accountName))
                .interpolationMethod(.monotone)
                .symbol(by: .value("Account", point.accountName))
            }
            .chartForegroundStyleScale(
                domain: trendAccounts.map { $0.name },
                range: trendAccounts.map { Color.fromHex($0.color) }
            )
            .chartXAxis {
                AxisMarks(values: Array(0..<trendMonthLabels.count)) { value in
                    AxisValueLabel {
                        if let i = value.as(Int.self), i >= 0, i < trendMonthLabels.count {
                            Text(trendMonthLabels[i])
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text(v.shortINR) } }
                }
            }
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 200)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                .kerning(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func accKpi(_ label: String, value: String, pct: Int?, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
            if let p = pct {
                let up = p >= 0
                HStack(spacing: 2) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    Text("\(up ? "+" : "")\(p)%")
                    Text(sub).lineLimit(1)
                }
                .font(.system(size: 9))
                .foregroundStyle(up ? .red : Color(hex: "#10b981"))
            } else {
                Text("— \(sub)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        isLoading = true
        async let accts = service.getAccounts()
        async let stats = service.getStats()
        do {
            let (a, s) = try await (accts, stats)
            accounts = a
            statsById = Dictionary(uniqueKeysWithValues: s.map { ($0.accountId, $0) })
        } catch {}
        isLoading = false
        await loadAccountSpend(for: period)
        await loadSpendTrend(for: period)
    }

    /// Recompute the "Spend by Account" donut for the given page-level period.
    private func loadAccountSpend(for period: DashboardPeriod) async {
        var filters = ExpenseFilters()
        filters.status = .submitted
        filters.from = period.periodStart
        filters.to = period.periodEnd
        filters.pageSize = 2000

        do {
            let result = try await expenseService.getExpenses(filters: filters)
            let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

            var totals: [String: Double] = [:]
            for e in result.items {
                guard let id = e.paymentAccountId else { continue }
                totals[id, default: 0] += e.amount
            }
            let grand = totals.values.reduce(0, +)

            byAccountSpend = totals.sorted { $0.value > $1.value }
                .enumerated()
                .compactMap { idx, kv -> AccountSpend? in
                    guard let acct = accountMap[kv.key] else { return nil }
                    return AccountSpend(
                        accountId: kv.key,
                        accountName: acct.name,
                        total: kv.value,
                        pct: grand > 0 ? Int((kv.value / grand) * 100) : 0,
                        color: acct.color ?? dashboardColors[idx % dashboardColors.count]
                    )
                }
        } catch {
            byAccountSpend = []
        }
    }

    /// Recompute the trailing 6-month per-account spend trend (top 5 accounts by window total).
    private func loadSpendTrend(for period: DashboardPeriod) async {
        let cal = Calendar.current
        // Anchor on the selected month (or the current month in Year mode); build 6 monthly buckets.
        let anchorStart: Date = period.mode == .month
            ? period.periodStart
            : cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let monthStarts: [Date] = (0..<6).reversed().compactMap {
            cal.date(byAdding: .month, value: -$0, to: anchorStart)
        }
        guard let first = monthStarts.first, let last = monthStarts.last,
              let windowEnd = cal.date(byAdding: .month, value: 1, to: last) else { return }

        var filters = ExpenseFilters()
        filters.status = .submitted
        filters.from = first
        filters.to = windowEnd
        filters.pageSize = 2000

        func bucketIndex(_ date: Date) -> Int? {
            let c = cal.dateComponents([.year, .month], from: date)
            return monthStarts.firstIndex { ms in
                let mc = cal.dateComponents([.year, .month], from: ms)
                return mc.year == c.year && mc.month == c.month
            }
        }

        do {
            let result = try await expenseService.getExpenses(filters: filters)
            let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

            var series: [String: [Double]] = [:]
            for e in result.items {
                guard let id = e.paymentAccountId, let idx = bucketIndex(e.transactionDate) else { continue }
                series[id, default: Array(repeating: 0, count: monthStarts.count)][idx] += e.amount
            }

            let f = DateFormatter(); f.dateFormat = "MMM"
            trendMonthLabels = monthStarts.map { f.string(from: $0) }

            let top = series.sorted { $0.value.reduce(0, +) > $1.value.reduce(0, +) }.prefix(5)
            var points: [AccountTrendPoint] = []
            for (i, entry) in top.enumerated() {
                guard let acct = accountMap[entry.key] else { continue }
                let color = acct.color ?? dashboardColors[i % dashboardColors.count]
                for (mi, v) in entry.value.enumerated() {
                    points.append(AccountTrendPoint(
                        accountId: entry.key, accountName: acct.name,
                        monthIndex: mi, total: v, color: color))
                }
            }
            spendTrend = points
        } catch {
            spendTrend = []
        }
    }
}

// MARK: - Account detail card

private struct AccountDetailCard: View {
    let account: PaymentAccount
    let stat: AccountStats?
    let isCard: Bool

    private var accentColor: Color {
        account.color.map { Color.fromHex($0) } ?? (isCard ? .accentColor : Color(hex: "#10b981"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Colored top border
            accentColor.frame(height: 3)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: isCard ? "creditcard" : "building.columns")
                            .font(.system(size: 16))
                            .foregroundStyle(accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(account.name).font(.subheadline.bold()).lineLimit(1)
                            if account.isDefault {
                                Text("Default")
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Text(account.accountType.displayName)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Bank + last4
                if account.bank != nil || account.last4 != nil {
                    HStack(spacing: 8) {
                        if let bank = account.bank {
                            Text(bank).font(.caption).foregroundStyle(.secondary)
                        }
                        if let last4 = account.last4 {
                            Text("•••• \(last4)").font(.caption)
                        }
                    }
                    .padding(.top, 8)
                }

                // Billing day
                if isCard, let day = account.billingDay {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.caption2).foregroundStyle(.secondary)
                        Text("Bills on the \(day)\(ordinal(day)) of each month")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                // Stats
                if let stat {
                    Divider().padding(.vertical, 10)
                    if isCard {
                        HStack(spacing: 20) {
                            statColumn("LAST BILLED",
                                       value: (stat.lastBilledAmount ?? 0).formattedINR,
                                       current: stat.lastBilledAmount ?? 0,
                                       prev: stat.lastBilledAmountPrev ?? 0,
                                       alertHigh: false)
                            statColumn("UNBILLED",
                                       value: (stat.unbilledAmount ?? 0).formattedINR,
                                       current: stat.unbilledAmount ?? 0,
                                       prev: stat.unbilledAmountPrev ?? 0,
                                       alertHigh: true)
                            Spacer()
                        }
                    } else {
                        HStack {
                            Text("THIS MONTH").font(.system(size: 9)).foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text((stat.thisMonthSpend ?? 0).formattedINR).font(.subheadline.bold())
                                pctChange(stat.thisMonthSpend ?? 0, stat.prevMonthSpend ?? 0,
                                          suffix: "vs \((stat.prevMonthSpend ?? 0).shortINR) last mo")
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statColumn(_ label: String, value: String,
                             current: Double, prev: Double, alertHigh: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold())
                .foregroundStyle(alertHigh && current > 0 ? .red : .primary)
            pctChange(current, prev, suffix: "")
        }
    }

    @ViewBuilder
    private func pctChange(_ current: Double, _ prev: Double, suffix: String) -> some View {
        if prev > 0 {
            let p = Int((current - prev) / prev * 100)
            let up = p >= 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                Text("\(up ? "+" : "")\(p)%\(suffix.isEmpty ? "" : " \(suffix)")")
                    .lineLimit(1)
            }
            .font(.system(size: 9))
            .foregroundStyle(up ? .red : Color(hex: "#10b981"))
        }
    }
}

// MARK: - Helpers

private func pct(_ current: Double, _ prev: Double) -> Int? {
    guard prev > 0 else { return current > 0 ? 100 : nil }
    return Int((current - prev) / prev * 100)
}

private func ordinal(_ n: Int) -> String {
    switch n {
    case 11, 12, 13: return "th"
    case _ where n % 10 == 1: return "st"
    case _ where n % 10 == 2: return "nd"
    case _ where n % 10 == 3: return "rd"
    default: return "th"
    }
}

private extension Color {
    init(hex: String) { self = Color.fromHex(hex) }
}
