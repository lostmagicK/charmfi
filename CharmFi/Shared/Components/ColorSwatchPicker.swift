import SwiftUI

/// A row of preset colour swatches plus a hex text field, used anywhere the user picks a hex
/// colour for a category, tag or income source. Mirrors Android's `ColorSwatchPicker`.
struct ColorSwatchPicker: View {
    @Binding var hex: String

    /// The dashboard's own series palette, not a separate one. Picking from a different set meant a
    /// category coloured here never matched the colour it was charted with. Mirrors Android, whose
    /// picker reads `DASHBOARD_COLORS` directly.
    static let palette = dashboardColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(Self.palette, id: \.self) { swatch in
                    Button {
                        hex = swatch
                    } label: {
                        Circle()
                            .fill(Color.fromHex(swatch))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().stroke(Color.primary, lineWidth: hex.caseInsensitiveCompare(swatch) == .orderedSame ? 2 : 0)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Circle().fill(Color.fromHex(hex)).frame(width: 20, height: 20)
                TextField("#RRGGBB", text: $hex)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
            }
        }
    }
}
