import SwiftUI
import Charts

struct HouseholdView: View {
    let period: DashboardPeriod
    @Environment(AuthState.self) private var authState
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var summary: HouseholdSummary?
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedMemberId: String? = nil
    @State private var dailyData: [HouseholdDailyPoint] = []
    @State private var expandedCategoryBuckets: Set<String> = []

    private var service: HouseholdService { HouseholdService(auth: authState) }
    private var isMonthMode: Bool { period.mode == .month }
    private var periodLabel: String { period.label }

    private func filteredRecent(_ s: HouseholdSummary) -> [HouseholdExpenseItem] {
        guard let uid = selectedMemberId else { return s.recent }
        return s.recent.filter { $0.ownerUserId == uid }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                VStack(spacing: 12) {
                    Image(systemName: "person.3").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let s = summary {
                householdContent(s)
            } else {
                ContentUnavailableView("No Household Data", systemImage: "person.3",
                    description: Text("Join a family group to see shared expenses"))
            }
        }
        .navigationTitle("Household")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await load() }
        .onChange(of: period) { _, _ in Task { await load() } }
    }

    @ViewBuilder
    private func householdContent(_ s: HouseholdSummary) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {

                // KPI — 4-up on iPad, 2×2 on iPhone
                if hSize == .regular {
                    HStack(alignment: .top, spacing: 8) {
                        hKpi(isMonthMode ? "Selected Month" : "Selected Year", value: s.totalThisMonth.formattedINR,
                             sub: "\(s.transactionCountThisMonth) txns")
                        hKpi("Year Total", value: s.totalThisYear.formattedINR, sub: "")
                        hKpi("My Share", value: s.myAmountThisMonth.formattedINR, sub: periodLabel)
                        hKpi("Shared", value: s.sharedAmountThisMonth.formattedINR, sub: periodLabel)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            hKpi(isMonthMode ? "Selected Month" : "Selected Year", value: s.totalThisMonth.formattedINR,
                                 sub: "\(s.transactionCountThisMonth) txns")
                            hKpi("Year Total", value: s.totalThisYear.formattedINR, sub: "")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 8) {
                            hKpi("My Share", value: s.myAmountThisMonth.formattedINR, sub: periodLabel)
                            hKpi("Shared", value: s.sharedAmountThisMonth.formattedINR, sub: periodLabel)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Stat cards — multi-column grid on iPad, single column on iPhone
                AdaptiveGrid(minColumnWidth: 360, spacing: 12) {
                    // Monthly trend — my vs shared, stacked
                    if !s.monthlyTrend.isEmpty {
                        hCard("Monthly Trend — Mine vs Shared") {
                            Chart(s.monthlyTrend) { p in
                                BarMark(
                                    x: .value("Month", p.shortLabel),
                                    y: .value("Amount", p.myAmount)
                                )
                                .foregroundStyle(by: .value("Type", "Mine"))

                                BarMark(
                                    x: .value("Month", p.shortLabel),
                                    y: .value("Amount", p.sharedAmount)
                                )
                                .foregroundStyle(by: .value("Type", "Shared"))
                            }
                            .chartForegroundStyleScale([
                                "Mine": Color.accentColor,
                                "Shared": Color.fromHex("#10b981")
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
                            .frame(height: 150)
                        }
                    }

                    // Daily Spend chart — Month mode only, driven by the shared page period
                    if isMonthMode {
                        hCard("Daily Spend") {
                            if dailyData.isEmpty {
                                Text("No data").font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                            } else {
                                DailyBarChart(data: dailyData).frame(height: 100)
                            }
                        }
                    }

                    // Member contribution donut
                    if s.byMember.count > 1 {
                        hCard("Member Contribution — \(periodLabel)") {
                            Chart(Array(s.byMember.enumerated()), id: \.element.id) { idx, m in
                                SectorMark(
                                    angle: .value("Amount", m.totalThisMonth),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(by: .value("Member", m.isOwn ? "\(m.displayName) (me)" : m.displayName))
                                .cornerRadius(3)
                            }
                            .chartForegroundStyleScale(range: donutColors(s.byMember.count))
                            .chartLegend(position: .bottom, spacing: 8)
                            .frame(height: 200)
                        }
                    }

                    // My share vs household, selected period
                    if (s.myAmountThisMonth + s.sharedAmountThisMonth) > 0 {
                        hCard("My Share — \(periodLabel)") {
                            let slices = [
                                ("Mine", s.myAmountThisMonth),
                                ("Shared", s.sharedAmountThisMonth)
                            ]
                            Chart(slices, id: \.0) { slice in
                                SectorMark(
                                    angle: .value("Amount", slice.1),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(by: .value("Type", slice.0))
                                .cornerRadius(3)
                            }
                            .chartForegroundStyleScale([
                                "Mine": Color.accentColor,
                                "Shared": Color.fromHex("#10b981")
                            ])
                            .chartLegend(position: .bottom, spacing: 8)
                            .frame(height: 180)
                        }
                    }

                    // By Categories — full-depth drilldown (same style as Personal dashboard)
                    if !s.byCategoryHierarchy.isEmpty {
                        hCard("By Categories — \(periodLabel)") {
                            let grand = max(s.byCategoryHierarchy.reduce(0) { $0 + $1.total }, 1)
                            VStack(spacing: 8) {
                                ForEach(Array(categoryTree(s.byCategoryHierarchy, grand: grand))) { bar in
                                    HouseholdCategoryBarTree(bar: bar, path: "root", depth: 0,
                                        barFraction: bar.total / grand, expanded: $expandedCategoryBuckets)
                                }
                            }
                        }
                    }
                }

                // Recent — with member filter chips
                if !s.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent").font(.subheadline.bold())

                        // Member filter chips (only when there are multiple members)
                        if s.byMember.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    chip("All", selected: selectedMemberId == nil) {
                                        selectedMemberId = nil
                                    }
                                    ForEach(s.byMember) { m in
                                        chip(m.isOwn ? "Me" : m.displayName,
                                             selected: selectedMemberId == m.userId) {
                                            selectedMemberId = m.userId
                                        }
                                    }
                                }
                            }
                        }

                        let visible = filteredRecent(s)
                        if visible.isEmpty {
                            Text("No transactions for this member")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        } else {
                            ForEach(visible) { e in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.merchant).font(.subheadline.bold()).lineLimit(1)
                                        Text("\(e.isOwn ? "Me" : e.ownerDisplayName) · \(String(e.transactionDate.prefix(10)))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(e.amount.formattedINR)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.accentColor)
                                }
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }

                Spacer().frame(height: 20)
            }
            .padding(16)
        }
        .refreshable { await load() }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    private func hKpi(_ label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            if !sub.isEmpty { Text(sub).font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func donutColors(_ count: Int) -> [Color] {
        (0..<max(count, 1)).map { Color.fromHex(dashboardColors[$0 % dashboardColors.count]) }
    }

    private func categoryTree(_ groups: [HouseholdCategoryGroup], grand: Double) -> [CategoryBar] {
        groups.enumerated().map { i, g in
            let color = dashboardColors[i % dashboardColors.count]
            let children = g.subcategories.map { sub in
                CategoryBar(name: sub.name, icon: sub.icon, total: sub.total,
                            pct: Int((sub.total / grand) * 100), color: color)
            }
            return CategoryBar(name: g.name, icon: g.icon, total: g.total,
                                pct: Int((g.total / grand) * 100), color: color, children: children)
        }
    }

    private func hCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold())
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            if isMonthMode {
                async let s = service.getSummary(year: period.year, month: period.month)
                async let d = service.getDaily(year: period.year, month: period.month)
                let (summaryResult, dailyResult) = try await (s, d)
                summary = summaryResult
                dailyData = dailyResult
            } else {
                summary = try await service.getSummary(year: period.year, month: nil)
                dailyData = []
            }
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

// MARK: - By Categories drilldown (mirrors the Personal dashboard's CategoryBarTree)

private struct HouseholdCategoryBarTree: View {
    let bar: CategoryBar
    let path: String
    let depth: Int
    let barFraction: Double
    @Binding var expanded: Set<String>

    private var key: String { "\(path)/\(bar.name)" }
    private var expandable: Bool {
        !bar.children.isEmpty && !(bar.children.count == 1 && bar.children[0].name == bar.name)
    }
    private var isExpanded: Bool { expandable && expanded.contains(key) }

    var body: some View {
        VStack(spacing: 8) {
            HouseholdBucketRow(
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
                        HouseholdCategoryBarTree(bar: child, path: key, depth: depth + 1,
                                        barFraction: bar.total > 0 ? child.total / bar.total : 0,
                                        expanded: $expanded)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct HouseholdBucketRow: View {
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
