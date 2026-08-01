import SwiftUI

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss

    let expense: Expense?
    let categories: [Category]
    let accounts: [PaymentAccount]
    var onSave: ((CreateExpenseRequest) async -> Void)?
    var onUpdate: ((UpdateExpenseRequest) async -> Void)?

    @State private var merchant = ""
    @State private var amount = ""
    @State private var paymentMethod: PaymentMethod = .upi
    @State private var transactionDate = Date()
    @State private var categoryId: String?
    @State private var accountId: String?
    @State private var comment = ""
    @State private var isSaving = false

    init(expense: Expense? = nil, categories: [Category], accounts: [PaymentAccount],
         onSave: ((CreateExpenseRequest) async -> Void)? = nil,
         onUpdate: ((UpdateExpenseRequest) async -> Void)? = nil) {
        self.expense = expense; self.categories = categories; self.accounts = accounts
        self.onSave = onSave; self.onUpdate = onUpdate
        if let e = expense {
            _merchant = State(initialValue: e.merchant)
            _amount = State(initialValue: String(e.amount))
            _paymentMethod = State(initialValue: e.paymentMethod)
            _transactionDate = State(initialValue: e.transactionDate)
            _categoryId = State(initialValue: e.categoryId)
            _accountId = State(initialValue: e.paymentAccountId)
            _comment = State(initialValue: e.comment ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Merchant", text: $merchant)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $transactionDate, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Payment") {
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    if !filteredAccounts.isEmpty {
                        Picker("Account", selection: $accountId) {
                            Text("None").tag(String?.none)
                            ForEach(filteredAccounts) { acc in
                                Text(acc.name).tag(Optional(acc.id))
                            }
                        }
                    }
                }
                Section("Category") {
                    CategoryPickerView(selectedCategoryId: $categoryId, categories: categories)
                }
                Section("Notes") {
                    TextField("Comment (optional)", text: $comment, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(merchant.isEmpty || amount.isEmpty || isSaving)
                }
            }
        }
    }

    private var filteredAccounts: [PaymentAccount] {
        accounts.filter { acc in
            switch paymentMethod {
            case .card: acc.accountType.isCard
            case .upi, .netBanking: !acc.accountType.isCard
            default: true
            }
        }
    }

    private func save() async {
        guard let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) else { return }
        isSaving = true
        if expense == nil {
            let req = CreateExpenseRequest(
                amount: amountValue, merchant: merchant, paymentMethod: paymentMethod,
                transactionDate: transactionDate, comment: comment.isEmpty ? nil : comment,
                categoryId: categoryId, paymentAccountId: accountId
            )
            await onSave?(req)
        } else {
            let req = UpdateExpenseRequest(
                amount: amountValue, merchant: merchant, paymentMethod: paymentMethod,
                transactionDate: transactionDate, comment: comment.isEmpty ? nil : comment,
                categoryId: categoryId, paymentAccountId: accountId
            )
            await onUpdate?(req)
        }
        isSaving = false
        dismiss()
    }
}
