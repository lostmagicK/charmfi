import SwiftUI

struct PaymentAccountsView: View {
    @Environment(AuthState.self) private var authState
    @State private var accounts: [PaymentAccount] = []
    @State private var stats: [AccountStats] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showAddSheet = false
    @State private var editingAccount: PaymentAccount?

    private var service: PaymentAccountService { PaymentAccountService(auth: authState) }

    var cardAccounts: [PaymentAccount] { accounts.filter { $0.accountType.isCard } }
    var otherAccounts: [PaymentAccount] { accounts.filter { !$0.accountType.isCard } }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if accounts.isEmpty {
                ContentUnavailableView("No Accounts", systemImage: "creditcard", description: Text("Tap + to add an account"))
            } else {
                List {
                    if let err = error {
                        ErrorBannerView(message: err) { self.error = nil }
                    }
                    if !cardAccounts.isEmpty {
                        Section("Cards") {
                            ForEach(cardAccounts) { acc in accountRow(acc) }
                        }
                    }
                    if !otherAccounts.isEmpty {
                        Section("Accounts & Wallets") {
                            ForEach(otherAccounts) { acc in accountRow(acc) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Payment Accounts")
        .adaptiveReadableWidth()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAddSheet) { accountFormSheet(account: nil) }
        .sheet(item: $editingAccount) { accountFormSheet(account: $0) }
    }

    private func accountRow(_ acc: PaymentAccount) -> some View {
        let stat = stats.first(where: { $0.accountId == acc.id })
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: acc.accountType.icon)
                    .foregroundStyle(acc.color.map { Color.fromHex($0) } ?? .accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(acc.name).font(.subheadline.bold())
                        if acc.isDefault {
                            Text("Default").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15)).foregroundStyle(Color.accentColor).clipShape(Capsule())
                        }
                    }
                    if let bank = acc.bank {
                        Text([bank, acc.last4.map { "····\($0)" }].compactMap { $0 }.joined(separator: " "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let stat {
                HStack {
                    if let tm = stat.thisMonthSpend { statPill("This month", amount: tm) }
                    if acc.accountType.isCredit, let lb = stat.lastBilledAmount { statPill("Last billed", amount: lb) }
                    if acc.accountType.isCredit, let ub = stat.unbilledAmount { statPill("Unbilled", amount: ub) }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await delete(id: acc.id) } } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { editingAccount = acc } label: {
                Label("Edit", systemImage: "pencil")
            }.tint(.blue)
            if !acc.isDefault {
                Button { Task { await setDefault(id: acc.id) } } label: {
                    Label("Set Default", systemImage: "star")
                }.tint(.yellow)
            }
        }
    }

    private func statPill(_ label: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(amount.formattedINR).font(.caption.bold())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func accountFormSheet(account: PaymentAccount?) -> some View {
        AccountFormSheet(account: account) { req in
            if let account {
                if let updated = try? await service.updateAccount(id: account.id, req: req) {
                    if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
                        accounts[idx] = updated
                    }
                }
            } else {
                if let created = try? await service.createAccount(req) {
                    accounts.append(created)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        async let accts = service.getAccounts()
        async let statsResult = service.getStats()
        do {
            let (a, s) = try await (accts, statsResult)
            accounts = a
            stats = s
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(id: String) async {
        do {
            try await service.deleteAccount(id: id)
            accounts.removeAll { $0.id == id }
        } catch { self.error = error.localizedDescription }
    }

    private func setDefault(id: String) async {
        do {
            try await service.setDefault(id: id)
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct AccountFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthState.self) private var authState
    let account: PaymentAccount?
    var onSave: (PaymentAccountRequest) async -> Void

    @State private var name = ""
    @State private var accountType: AccountType = .savings
    @State private var bank = ""
    @State private var last4 = ""
    @State private var billingDay = ""
    @State private var color = "#3b82f6"
    @State private var banks: [Bank] = []

    init(account: PaymentAccount?, onSave: @escaping (PaymentAccountRequest) async -> Void) {
        self.account = account; self.onSave = onSave
        if let a = account {
            _name = State(initialValue: a.name)
            _accountType = State(initialValue: a.accountType)
            _bank = State(initialValue: a.bank ?? "")
            _last4 = State(initialValue: a.last4 ?? "")
            _billingDay = State(initialValue: a.billingDay.map { String($0) } ?? "")
            _color = State(initialValue: a.color ?? "#3b82f6")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Account Name", text: $name)
                Picker("Type", selection: $accountType) {
                    ForEach(AccountType.allCases) { t in Text(t.displayName).tag(t) }
                }
                if banks.isEmpty {
                    TextField("Bank (optional)", text: $bank)
                } else {
                    Picker("Bank", selection: $bank) {
                        Text("None").tag("")
                        ForEach(banks) { b in Text(b.name).tag(b.name) }
                    }
                }
                TextField("Last 4 digits", text: $last4).keyboardType(.numberPad)
                if accountType.isCredit {
                    TextField("Billing Day (1-28)", text: $billingDay).keyboardType(.numberPad)
                }
                Section("Color") {
                    ColorSwatchPicker(hex: $color)
                }
            }
            .navigationTitle(account == nil ? "Add Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                banks = (try? await BanksService(auth: authState).getBanks()) ?? []
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let req = PaymentAccountRequest(
                            name: name, accountType: accountType,
                            bank: bank.isEmpty ? nil : bank,
                            last4: last4.isEmpty ? nil : last4,
                            color: color,
                            billingDay: Int(billingDay)
                        )
                        Task { await onSave(req); dismiss() }
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
