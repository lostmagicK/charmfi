import SwiftUI

/// A row of preset colour swatches plus a hex text field, used anywhere the user picks a hex
/// colour for a category, tag or income source. Mirrors Android's `ColorSwatchPicker`.
struct ColorSwatchPicker: View {
    @Binding var hex: String

    static let palette = [
        "#ef4444", "#f97316", "#f59e0b", "#84cc16", "#10b981",
        "#06b6d4", "#3b82f6", "#8b5cf6", "#ec4899", "#64748b"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
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
