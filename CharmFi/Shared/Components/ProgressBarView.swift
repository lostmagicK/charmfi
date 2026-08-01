import SwiftUI

struct ProgressBarView: View {
    let spent: Double
    let total: Double
    var showLabel: Bool = true

    private var fraction: Double { total > 0 ? min(spent / total, 1.0) : 0 }
    private var isOver: Bool { spent > total }

    private var barColor: Color {
        if isOver || fraction >= 0.9 { return Color(hex: "#ef4444") }  // red
        if fraction >= 0.7 { return Color(hex: "#f59e0b") }             // amber
        return Color(hex: "#10b981")                                      // green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            if showLabel {
                HStack {
                    Text(spent.formattedINR).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(total.formattedINR).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension Color {
    init(hex: String) { self = Color.fromHex(hex) }
}
