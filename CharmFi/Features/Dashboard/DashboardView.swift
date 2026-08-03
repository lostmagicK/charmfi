import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AuthState.self) private var authState
    @State private var vm: DashboardViewModel?
    @State private var period: DashboardPeriod = .current()

    /// Reads and writes through to the cached view model so the section outlives a rotation.
    private var selectedSection: Binding<Int> {
        Binding(get: { vm?.selectedSection ?? 0 },
                set: { vm?.selectedSection = $0 })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: selectedSection) {
                    Text("Personal").tag(0)
                    Text("Household").tag(1)
                    Text("Accounts").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                PeriodNavBar(period: $period)
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                if let vm {
                    switch vm.selectedSection {
                    case 0: PersonalTab(vm: vm)
                    case 1: HouseholdView(period: period).environment(authState)
                    case 2: DashboardAccountsView(period: period).environment(authState)
                    default: EmptyView()
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await vm?.load(period: period) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            let (model, isNew) = ViewModelStore.shared.model(DashboardViewModel.self, auth: authState)
            vm = model
            if isNew {
                await model.load(period: period)
            } else {
                // Reusing a model from before a layout rebuild: adopt the period it holds
                // so the nav bar doesn't snap back to the current month.
                period = model.period
            }
        }
        .onChange(of: period) { _, newPeriod in
            Task { await vm?.load(period: newPeriod) }
        }
    }
}

// MARK: - Personal Tab

private struct PersonalTab: View {
    let vm: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var expandedBuckets: Set<String> = []

    private var isMonthMode: Bool { vm.period.mode == .month }
    private var periodLabel: String { vm.period.label }
    private var prevPeriodLabel: String { vm.period.prev().label }

    var body: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { ScrollView {
            if let err = vm.error {
                ErrorBannerView(message: err) { vm.error = nil }.padding()
            }

            LazyVStack(spacing: 12) {
                // Row 1 — KPI cards (4-up on iPad, 2×2 on iPhone)
                kpiGrid

                if hSize == .regular {
                    // iPad — flow all cards into a multi-column grid
                    AdaptiveGrid(minColumnWidth: 360, spacing: 12) {
                        // Time trends
                        if isMonthMode { spendPaceCard }
                        monthlySpendCard
                        if isMonthMode { dailySpendCard }
                        // Savings
                        if !vm.savingsSeries.isEmpty { savingsPerMonthCard }
                        if vm.savingsRateTrend.contains(where: { $0.rate != nil }) { savingsRateCard }
                        // Category breakdown
                        categoryCard
                        if !vm.byCategory.isEmpty { byBucketCard }
                        if !vm.categoryDeltas.isEmpty { categoryCompareCard }
                        // Behavior — By Method before By Weekday
                        if !vm.byMethod.isEmpty { byMethodCard }
                        weekdayCard
                        // Merchants & recent
                        topMerchantsCard
                        recentCard
                    }
                } else {
                    // iPhone — single column, same order as iPad
                    // Time trends
                    if isMonthMode { spendPaceCard }
                    monthlySpendCard
                    if isMonthMode { dailySpendCard }
                    // Savings
                    if !vm.savingsSeries.isEmpty { savingsPerMonthCard }
                    if vm.savingsRateTrend.contains(where: { $0.rate != nil }) { savingsRateCard }
                    // Category breakdown
                    categoryCard
                    if !vm.byCategory.isEmpty { byBucketCard }
                    if !vm.categoryDeltas.isEmpty { categoryCompareCard }
                    // Behavior — By Method before By Weekday
                    if !vm.byMethod.isEmpty { byMethodCard }
                    weekdayCard
                    // Merchants & recent — full width so the bar chart has room
                    topMerchantsCard
                    recentCard
                }

                Spacer().frame(height: 20)
            }
            .padding(12)
        }
        .refreshable { await vm.load(period: vm.period) }
        } // end else
    }

    // MARK: KPI grid

    @ViewBuilder private var kpiSelectedPeriod: some View {
        KPICard(label: isMonthMode ? "SELECTED MONTH" : "SELECTED YEAR",
                value: vm.thisMonthTotal.formattedINR,
                pct: changePct(vm.thisMonthTotal, vm.lastMonthTotal),
                sub: "vs \(prevPeriodLabel) \(vm.lastMonthTotal.shortINR)")
    }
    @ViewBuilder private var kpiYearTotal: some View {
        KPICard(label: "YEAR TOTAL", value: vm.thisYearTotal.formattedINR)
    }
    @ViewBuilder private var kpiCardOutstanding: some View {
        KPICard(label: "CARD OUTSTANDING",
                value: vm.cardOutstanding.formattedINR,
                pct: changePct(vm.cardOutstanding, vm.cardOutstandingPrev),
                sub: "vs last cycle \(vm.cardOutstandingPrev.shortINR)")
    }
    @ViewBuilder private var kpiCardUnbilled: some View {
        KPICard(label: "CARD UNBILLED",
                value: vm.cardUnbilled.formattedINR,
                pct: changePct(vm.cardUnbilled, vm.cardUnbilledPrev),
                sub: "vs prev \(vm.cardUnbilledPrev.shortINR)")
    }
    @ViewBuilder private var kpiSaved: some View {
        KPICard(label: "SAVED",
                value: vm.savedThisPeriod.formattedINR,
                pct: changePct(vm.savedThisPeriod, vm.savedPrevPeriod),
                sub: "vs \(prevPeriodLabel) \(vm.savedPrevPeriod.shortINR)",
                upIsGood: true)
    }
    @ViewBuilder private var kpiSavingsRate: some View {
        KPICard(label: "SAVINGS RATE",
                value: vm.savingsRatePct.map { "\($0)%" } ?? "—",
                sub: vm.incomeThisPeriod > 0 ? "of \(vm.incomeThisPeriod.shortINR) income" : "no income recorded")
    }

    private var kpiGrid: some View {
        Group {
            if hSize == .regular {
                // iPad — all six KPIs in a single row
                HStack(alignment: .top, spacing: 8) {
                    kpiSelectedPeriod
                    kpiYearTotal
                    kpiCardOutstanding
                    kpiCardUnbilled
                    kpiSaved
                    kpiSavingsRate
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                // iPhone — 2×3 grid
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        kpiSelectedPeriod
                        kpiYearTotal
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 8) {
                        kpiCardOutstanding
                        kpiCardUnbilled
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 8) {
                        kpiSaved
                        kpiSavingsRate
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Category donut

    private var categoryCard: some View {
        DashCard(title: "Spending by Category", subtitle: periodLabel) {
            if vm.thisMonthByCategory.isEmpty {
                Text("No data").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(vm.thisMonthByCategory) { bar in
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
                        Text(vm.thisMonthTotal.formattedINR)
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.accentColor)
                        ForEach(Array(vm.thisMonthByCategory.prefix(5))) { bar in
                            HStack(spacing: 5) {
                                Circle().fill(Color.fromHex(bar.color)).frame(width: 8, height: 8)
                                Text("\(bar.icon ?? "") \(bar.name)".trimmingCharacters(in: .whitespaces))
                                    .font(.caption2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(bar.pct)%").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Spend pace (selected vs previous period)

    private var spendPaceCard: some View {
        DashCard(title: "Spend Pace", subtitle: "\(periodLabel) vs \(prevPeriodLabel)") {
            if vm.spendPace.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(vm.spendPace) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Cumulative", point.amount)
                    )
                    .foregroundStyle(by: .value("Period", point.period))
                    .interpolationMethod(.monotone)
                }
                .chartForegroundStyleScale([
                    "This Month": Color.accentColor,
                    "Last Month": Color.secondary
                ])
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(v.shortINR) }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 170)
            }
        }
    }

    // MARK: Category — selected vs previous period

    private var categoryCompareCard: some View {
        DashCard(title: "Category", subtitle: "\(periodLabel) vs \(prevPeriodLabel)") {
            Chart(vm.categoryDeltas) { cat in
                BarMark(
                    x: .value("Amount", cat.thisMonth),
                    y: .value("Category", cat.name)
                )
                .foregroundStyle(by: .value("Period", "This Month"))
                .position(by: .value("Period", "This Month"))

                BarMark(
                    x: .value("Amount", cat.lastMonth),
                    y: .value("Category", cat.name)
                )
                .foregroundStyle(by: .value("Period", "Last Month"))
                .position(by: .value("Period", "Last Month"))
            }
            .chartForegroundStyleScale([
                "This Month": Color.accentColor,
                "Last Month": Color.secondary
            ])
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: max(140, CGFloat(vm.categoryDeltas.count) * 44))
        }
    }

    // MARK: Spending by weekday

    private var weekdayCard: some View {
        DashCard(title: "By Weekday", subtitle: periodLabel) {
            if vm.byWeekday.allSatisfy({ $0.total == 0 }) {
                Text("No data").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(vm.byWeekday) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Total", day.total)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(v.shortINR) }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
    }

    // MARK: Monthly trend

    private var monthlySpendCard: some View {
        DashCard(title: "Monthly Spend") {
            Chart(vm.monthlyTrend) { bar in
                BarMark(
                    x: .value("Month", bar.label),
                    y: .value("Spend", bar.total)
                )
                .foregroundStyle(bar.isCurrent ? Color.accentColor : Color.accentColor.opacity(0.35))
                .cornerRadius(4)
                .annotation(position: .top) {
                    if bar.total > 0 {
                        Text(bar.total.shortINR)
                            .font(.system(size: 8))
                            .foregroundStyle(bar.isCurrent ? Color.accentColor : Color.secondary)
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 130)
        }
    }

    // MARK: Daily Spend

    private var dailySpendCard: some View {
        DashCard(title: "Daily Spend", subtitle: periodLabel) {
            if vm.dailyData.isEmpty {
                Text("No daily data").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                DailyBarChart(data: vm.dailyData)
                    .frame(height: 120)
            }
        }
    }

    // MARK: Saved per Month

    private var savingsPerMonthCard: some View {
        DashCard(title: "Saved per Month") {
            Chart {
                ForEach(vm.savingsSeries) { series in
                    ForEach(Array(zip(vm.monthlyTrend, series.values)), id: \.0.id) { month, value in
                        BarMark(
                            x: .value("Month", month.label),
                            y: .value("Saved", value)
                        )
                        .foregroundStyle(by: .value("Bucket", series.name))
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: vm.savingsSeries.map(\.name),
                range: vm.savingsSeries.map { Color.fromHex($0.color) }
            )
            .chartLegend(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 130)

            SavingsLegend(series: vm.savingsSeries)
        }
    }

    // MARK: Savings Rate

    private var savingsRateCard: some View {
        DashCard(title: "Savings Rate") {
            Chart {
                ForEach(vm.savingsRateTrend) { point in
                    if let rate = point.rate {
                        LineMark(x: .value("Month", point.label), y: .value("Rate", rate))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Color.accentColor)
                        PointMark(x: .value("Month", point.label), y: .value("Rate", rate))
                            .foregroundStyle(point.isCurrent ? Color.accentColor : Color.accentColor.opacity(0.6))
                    }
                }
                RuleMark(y: .value("Target", savingsRateTargetPct))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text("\(v)%") }
                    }
                }
            }
            .frame(height: 130)

            TargetLegend(targetPct: savingsRateTargetPct)
        }
    }

    // MARK: By Categories

    private var byBucketCard: some View {
        DashCard(title: "By Categories", subtitle: periodLabel) {
            let grand = max(vm.byCategory.reduce(0) { $0 + $1.total }, 1)
            VStack(spacing: 8) {
                ForEach(Array(vm.byCategory.prefix(6))) { bar in
                    CategoryBarTree(bar: bar, path: "root", depth: 0,
                                    barFraction: bar.total / grand, expanded: $expandedBuckets)
                }
            }
        }
    }

    // MARK: Recent + Top Merchants

    private var recentCard: some View {
        DashCard(title: "Recent") {
            VStack(spacing: 10) {
                ForEach(Array(vm.recentExpenses.prefix(5))) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.merchant).font(.caption).bold().lineLimit(1)
                            Text(e.transactionDate.shortDateString).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(e.amount.formattedINR).font(.caption.bold()).foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var topMerchantsCard: some View {
        DashCard(title: "Top Merchants", subtitle: periodLabel) {
            if vm.topMerchants.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(Array(vm.topMerchants.prefix(6))) { m in
                    BarMark(
                        x: .value("Total", m.total),
                        y: .value("Merchant", m.name)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(m.total.shortINR).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(preset: .aligned, position: .leading) { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 90, alignment: .leading)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.frame(minWidth: 80) }
                .frame(height: max(120, CGFloat(min(vm.topMerchants.count, 6)) * 36))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: By Method

    private var byMethodCard: some View {
        DashCard(title: "By Method", subtitle: periodLabel) {
            Chart(vm.byMethod) { m in
                SectorMark(
                    angle: .value("Total", m.total),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Method", methodLabel(m.method)))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(
                domain: vm.byMethod.map { methodLabel($0.method) },
                range: vm.byMethod.map { Color.fromHex($0.color) }
            )
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 200)
        }
    }
}

// MARK: - Daily Bar Chart

struct DailyBarChart: View {
    let data: [HouseholdDailyPoint]

    var body: some View {
        let maxVal = data.map(\.total).max() ?? 1
        Chart(data) { point in
            BarMark(
                x: .value("Day", point.day),
                y: .value("Spend", point.total)
            )
            .foregroundStyle(
                (maxVal > 0 && point.total / maxVal > 0.8)
                ? Color.red.opacity(0.75)
                : Color.accentColor.opacity(0.7)
            )
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 5)) { value in
                AxisValueLabel {
                    if let d = value.as(Int.self) { Text("\(d)") }
                }
            }
        }
        .chartYAxis(.hidden)
    }
}

// MARK: - Sub-components

// Recursively renders a CategoryBar and — while expanded — its children, to unlimited depth.
// A node is expandable when it has more than one child, or its single child isn't just the
// "direct spend on this category" placeholder row (same name as the node itself).
private struct CategoryBarTree: View {
    let bar: CategoryBar
    let path: String
    let depth: Int
    let barFraction: Double   // bar fill relative to parent; pct text stays global
    @Binding var expanded: Set<String>

    private var key: String { "\(path)/\(bar.name)" }
    private var expandable: Bool {
        !bar.children.isEmpty && !(bar.children.count == 1 && bar.children[0].name == bar.name)
    }
    private var isExpanded: Bool { expandable && expanded.contains(key) }

    var body: some View {
        VStack(spacing: 8) {
            BucketRow(
                label: "\(bar.icon ?? "") \(bar.name)".trimmingCharacters(in: .whitespaces),
                pct: bar.pct,
                amount: bar.total,
                color: bar.color,
                barFraction: barFraction,
                indent: CGFloat(depth) * 16,
                showChevron: expandable,
                isExpanded: isExpanded,
                onTap: expandable ? {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded { expanded.remove(key) } else { expanded.insert(key) }
                    }
                } : nil
            )
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(bar.children) { child in
                        CategoryBarTree(bar: child, path: key, depth: depth + 1,
                                        barFraction: bar.total > 0 ? child.total / bar.total : 0,
                                        expanded: $expanded)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// Single bucket/category row: optional chevron, label, fill bar, percentage, amount.
private struct BucketRow: View {
    let label: String
    let pct: Int
    let amount: Double
    let color: String
    var barFraction: Double = 0
    var indent: CGFloat = 0
    var showChevron: Bool = false
    var isExpanded: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(Color.fromHex(color))
                        .frame(width: geo.size.width * CGFloat(min(max(barFraction, 0), 1)))
                }
            }
            .frame(height: 8)
            Text("\(pct)%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            Text(amount.shortINR)
                .font(.caption2.bold())
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.leading, indent)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

/// Wraps the "Saved per Month" stacked bar chart — one dot + label per savings bucket.
private struct SavingsLegend: View {
    let series: [SavingsSeries]

    var body: some View {
        if !series.isEmpty {
            let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(series) { s in
                    HStack(spacing: 4) {
                        Circle().fill(Color.fromHex(s.color)).frame(width: 8, height: 8)
                        Text("\(s.icon ?? "") \(s.name)".trimmingCharacters(in: .whitespaces))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// Caption under the "Savings Rate" chart explaining the dashed target line.
private struct TargetLegend: View {
    let targetPct: Int

    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(.secondary).frame(width: 12, height: 1)
            Text("Target \(targetPct)%").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct DashCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.bold())
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Color.accentColor)
                }
            }
            content()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Single card used for all KPIs — Spacer() makes every card fill the row height equally
private struct KPICard: View {
    let label: String
    let value: String
    var pct: Int? = nil
    var sub: String? = nil
    /// Most KPIs are spend-like — up is bad (red), down is good (green). SAVED is the inverse.
    var upIsGood: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            if let sub { Text(sub).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
            if let pct {
                let isGood = upIsGood ? pct >= 0 : pct < 0
                HStack(spacing: 3) {
                    Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(abs(pct))%")
                }
                .font(.system(size: 10))
                .foregroundStyle(isGood ? .green : .red)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// Alias kept for call-site clarity
private typealias AccountKPICard = KPICard

// MARK: - Helpers

private func changePct(_ current: Double, _ previous: Double) -> Int? {
    guard previous > 0 else { return nil }
    return Int(((current - previous) / previous) * 100)
}

private func methodLabel(_ method: String) -> String {
    switch method {
    case "NetBanking": return "Net Banking"
    case "Upi": return "UPI"
    case "FastTag": return "FASTag"
    default: return method
    }
}
