import SwiftUI

struct MutuusView: View {
    @Environment(AuthState.self) private var authState
    @State private var balances: [FamilyMemberBalance] = []
    @State private var log: [SharedExpenseLogEntry] = []
    @State private var selectedUserId: String?
    @State private var isLoading = false
    @State private var error: String?
    @State private var settleMember: FamilyMemberBalance?

    private var service: FamilyGroupService { FamilyGroupService(auth: authState) }

    var filteredLog: [SharedExpenseLogEntry] {
        guard let uid = selectedUserId else { return log }
        return log.filter { $0.payerUserId == uid || $0.recipientUserId == uid }
    }

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else {
                ScrollView {
                    if let err = error {
                        ErrorBannerView(message: err) { self.error = nil }.padding()
                    }
                    if !balances.isEmpty {
                        balanceCards
                    }
                    if !log.isEmpty {
                        logSection
                    }
                }
            }
        }
        .navigationTitle("Mutuus")
        .adaptiveReadableWidth()
        .task { await load() }
        .sheet(item: $settleMember) { member in
            SettleSheet(member: member, service: service, accountService: PaymentAccountService(auth: authState)) { await load() }
        }
    }

    private var balanceCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Balances").font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(balances) { balance in
                        balanceCard(balance)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private func balanceCard(_ b: FamilyMemberBalance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(b.displayName).font(.subheadline.bold()).lineLimit(1)
            HStack(spacing: 4) {
                Circle()
                    .fill(b.netBalance >= 0 ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(b.netBalance >= 0 ? "Owe me" : "I owe")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(abs(b.netBalance).formattedINR).font(.title3.bold())
                .foregroundStyle(b.netBalance >= 0 ? .green : .red)
            Button("Settle") { settleMember = b }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onTapGesture { selectedUserId = selectedUserId == b.userId ? nil : b.userId }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selectedUserId == b.userId ? Color.accentColor : .clear, lineWidth: 2)
        )
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transaction Log").font(.headline).padding(.horizontal)
            ForEach(filteredLog) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entryIcon(entry))
                        .foregroundStyle(entryColor(entry))
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.merchant ?? entry.type.rawValue).font(.subheadline)
                        Text("\(entry.payerDisplayName) → \(entry.recipientDisplayName)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.transactionDate.shortDateString)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.amount.formattedINR).font(.subheadline.bold())
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                Divider().padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private func entryIcon(_ e: SharedExpenseLogEntry) -> String {
        switch e.type {
        case .expense: "arrow.up.circle"
        case .approved: "checkmark.circle"
        case .deleted: "xmark.circle"
        case .settlement: "arrow.left.arrow.right.circle"
        }
    }

    private func entryColor(_ e: SharedExpenseLogEntry) -> Color {
        switch e.type {
        case .expense: .blue
        case .approved: .green
        case .deleted: .red
        case .settlement: .purple
        }
    }

    private func load() async {
        isLoading = true
        async let b = service.getBalances()
        async let l = service.getExpenseLog()
        balances = (try? await b) ?? []
        log = (try? await l) ?? []
        isLoading = false
    }
}

struct SettleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let member: FamilyMemberBalance
    let service: FamilyGroupService
    let accountService: PaymentAccountService
    var onDone: () async -> Void

    @State private var amount = ""
    @State private var paymentMethod: PaymentMethod = .upi
    @State private var accountId: String? = nil
    @State private var date = Date()
    @State private var comment = ""
    @State private var accounts: [PaymentAccount] = []

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Settling with", value: member.displayName)
                TextField("Amount", text: $amount).keyboardType(.decimalPad)
                Picker("Payment Method", selection: $paymentMethod) {
                    ForEach(PaymentMethod.allCases) { m in Text(m.displayName).tag(m) }
                }
                if !accounts.isEmpty {
                    Picker("Account", selection: $accountId) {
                        Text("None").tag(String?.none)
                        ForEach(accounts) { acc in Text(acc.name).tag(Optional(acc.id)) }
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Comment (optional)", text: $comment)
            }
            .navigationTitle("Settle Payment")
            .navigationBarTitleDisplayMode(.inline)
            .task { accounts = (try? await accountService.getAccounts())?.filter(\.isActive) ?? [] }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Settle") {
                        guard let val = Double(amount) else { return }
                        let req = SettleRequest(
                            recipientUserId: member.userId, amount: val,
                            paymentMethod: paymentMethod,
                            paymentAccountId: accountId,
                            comment: comment.isEmpty ? nil : comment,
                            transactionDate: date
                        )
                        Task {
                            try? await service.settle(req)
                            await onDone()
                            dismiss()
                        }
                    }.disabled(amount.isEmpty)
                }
            }
        }
    }
}
