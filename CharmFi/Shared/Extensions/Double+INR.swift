import Foundation

extension Double {
    var formattedINR: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.locale = Locale(identifier: "en_IN")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "₹\(self)"
    }

    var shortINR: String {
        if self >= 1_00_000 {
            return String(format: "₹%.1fL", self / 1_00_000)
        } else if self >= 1_000 {
            return String(format: "₹%.1fK", self / 1_000)
        }
        return formattedINR
    }
}
