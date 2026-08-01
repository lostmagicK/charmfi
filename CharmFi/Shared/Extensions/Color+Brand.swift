import SwiftUI

extension Color {
    static let brand = Color.accentColor

    static func fromHex(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return .gray }
        return Color(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }

    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    static func forPaymentMethod(_ method: PaymentMethod) -> Color {
        switch method {
        case .upi: .blue
        case .card: .purple
        case .cash: .green
        case .netBanking: .orange
        case .fastTag: .yellow
        case .other: .gray
        }
    }
}
