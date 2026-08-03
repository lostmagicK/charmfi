import SwiftUI

/// Page-level [<] Mar 2026 [>] navigator, optionally with a Month/Year granularity toggle.
///
/// `allowFuture` and `showJumpToPresent` are opt-in because most pages have no data ahead of today.
/// Budgets does: a default applies to every month, so future months are meaningful there. Mirrors
/// Android's `PeriodNavBar` (ui/components/PeriodNav.kt).
struct PeriodNavBar: View {
    @Binding var period: DashboardPeriod
    var showModeToggle: Bool = true
    var allowFuture: Bool = false
    var showJumpToPresent: Bool = false

    private static let forwardMonths = 12

    private var periodOptions: [DashboardPeriod] {
        let cal = Calendar.current
        let now = Date()
        let forward = allowFuture ? Self.forwardMonths : 0
        var base: [DashboardPeriod]
        if period.mode == .month {
            base = (0..<(24 + forward)).map { i -> DashboardPeriod in
                let d = cal.date(byAdding: .month, value: forward - i, to: now)!
                let c = cal.dateComponents([.year, .month], from: d)
                return DashboardPeriod(year: c.year!, month: c.month!, mode: .month)
            }
        } else {
            let forwardYears = (forward + 11) / 12
            let y = cal.component(.year, from: now)
            base = (0..<(6 + forwardYears)).map {
                DashboardPeriod(year: y + forwardYears - $0, month: period.month, mode: .year)
            }
        }
        // Arrowing past the option window must still leave a matching entry, or the menu shows no
        // selection at all.
        if !base.contains(period) {
            base = (base + [period]).sorted {
                ($0.year, $0.mode == .month ? $0.month : 0) > ($1.year, $1.mode == .month ? $1.month : 0)
            }
        }
        return base
    }

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Button { period = period.prev() } label: {
                    Image(systemName: "chevron.left")
                }
                Menu {
                    ForEach(periodOptions, id: \.self) { opt in
                        Button(opt.label) { period = opt }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(period.label).font(.subheadline.bold())
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .frame(minWidth: 72)
                }
                Button { period = period.next() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!allowFuture && period.isAtPresent)
                // Only rendered once the user has drifted, so it never adds noise at the default position.
                if showJumpToPresent && !period.isAtPresent {
                    Button {
                        period = DashboardPeriod.current().withMode(period.mode)
                    } label: {
                        Label(period.mode == .month ? "This month" : "This year",
                              systemImage: "arrow.counterclockwise")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Spacer()
            if showModeToggle {
                HStack(spacing: 6) {
                    modeChip("Month", selected: period.mode == .month) { period = period.withMode(.month) }
                    modeChip("Year", selected: period.mode == .year) { period = period.withMode(.year) }
                }
            }
        }
    }

    private func modeChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
