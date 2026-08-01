import SwiftUI

struct ErrorBannerView: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}
