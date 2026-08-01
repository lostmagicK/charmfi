import SwiftUI

struct FailedEmailDetailView: View {
    let email: FailedScanEmail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Parsed details card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Parsed Data")
                            .font(.caption.uppercaseSmallCaps())
                            .foregroundStyle(.secondary)

                        if let amount = email.parsedAmount {
                            row(label: "Amount", value: "₹\(String(format: "%.2f", amount))")
                        }
                        if let merchant = email.parsedMerchant {
                            row(label: "Merchant", value: merchant)
                        }
                        row(label: "Error", value: email.errorMessage, valueColor: .red)
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                    // Stripped email body
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Stripped Email Body")
                                .font(.caption.uppercaseSmallCaps())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = email.strippedBody
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                        }

                        Text(email.strippedBody.isEmpty ? "(empty)" : email.strippedBody)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle(email.subject.isEmpty ? "Failed Email" : email.subject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
        }
    }
}
