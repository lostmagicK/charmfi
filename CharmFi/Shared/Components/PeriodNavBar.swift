import SwiftUI

/// Page-level [<] Mar 2026 [>] navigator, optionally with a Month/Year granularity toggle.
struct PeriodNavBar: View {
    @Binding var period: DashboardPeriod
    var showModeToggle: Bool = true

    private var periodOptions: [DashboardPeriod] {
        let cal = Calendar.current
        let now = Date()
        if period.mode == .month {
            return (0..<24).map { i -> DashboardPeriod in
                let d = cal.date(byAdding: .month, value: -i, to: now)!
                let c = cal.dateComponents([.year, .month], from: d)
                return DashboardPeriod(year: c.year!, month: c.month!, mode: .month)
            }
        } else {
            let y = cal.component(.year, from: now)
            return (0..<6).map { DashboardPeriod(year: y - $0, month: period.month, mode: .year) }
        }
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
                .disabled(period.isAtPresent)
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
