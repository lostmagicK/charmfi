import SwiftUI

struct PaymentMethodBadge: View {
    let method: PaymentMethod

    var body: some View {
        Text(method.displayName)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.forPaymentMethod(method).opacity(0.15))
            .foregroundStyle(Color.forPaymentMethod(method))
            .clipShape(Capsule())
    }
}
