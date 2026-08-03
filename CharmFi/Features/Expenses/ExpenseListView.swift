import SwiftUI

struct ExpenseListView: View {
    @Environment(AuthState.self) private var authState
    @State private var vm: ExpenseListViewModel?
    @State private var editingExpense: Expense?
    @State private var taggingExpense: Expense?
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm { expenseContent(vm: vm) }
                else { ProgressView() }
            }
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let vm {
                        Button { vm.showFilters.toggle() } label: {
                            Image(systemName: vm.hasActiveFilters
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let vm { Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") } }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .shadow(radius: 4)
                }
                .padding(20)
            }
        }
        .task {
            let (model, isNew) = ViewModelStore.shared.model(ExpenseListViewModel.self, auth: authState)
            vm = model
            if isNew { await model.initialLoad() }
        }
        .sheet(item: $editingExpense) { e in
            if let vm {
                EditExpenseSheet(expense: e, categories: vm.categories) { merchant, comment, catId, method in
                    Task { await vm.updateExpense(id: e.id, merchant: merchant, comment: comment,
                                                  categoryId: catId, paymentMethod: method) }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            if let vm {
                AddExpenseSheet(
                    categories: vm.categories,
                    accounts: vm.accounts,
                    familyMembers: vm.familyMembers,
                    onSave: { amount, merchant, method, date, comment, catId, accountId, paidFor in
                        Task { await vm.createExpense(amount: amount, merchant: merchant,
                                                      paymentMethod: method, date: date,
                                                      comment: comment, categoryId: catId,
                                                      accountId: accountId, paidForUserId: paidFor) }
                    },
                    onSettle: { amount, method, recipientUserId, date, accountId, comment in
                        Task { await vm.settle(recipientUserId: recipientUserId, amount: amount,
                                               method: method, accountId: accountId, comment: comment, date: date) }
                    }
                )
            }
        }
        .sheet(item: $taggingExpense) { expense in
            if let vm {
                TagPickerSheet(
                    allTags: vm.allTags,
                    initialSelectedIds: Set(expense.tags.map(\.id)),
                    readOnly: expense.inheritedTags,
                    readOnlyCaption: "Inherited from category — change these on the category",
                    onCreateTag: { await vm.createTag($0) },
                    onSave: { ids in Task { await vm.setExpenseTags(id: expense.id, tagIds: Array(ids)) } }
                )
            }
        }
    }

    @ViewBuilder
    private func expenseContent(vm: ExpenseListViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DatePreset.allCases, id: \.self) { preset in
                        FilterChip(preset.rawValue, selected: vm.datePreset == preset) {
                            vm.applyPreset(preset)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            if vm.showFilters { FiltersPanel(vm: vm) }

            if vm.total > 0 {
                HStack {
                    Text("\(vm.total) expenses · page \(vm.page)/\(vm.totalPages)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(vm.totalAmount.formattedINR).font(.caption.bold()).foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color(.systemGray6))
            }

            // Above the loading/empty/content switch: a failed load leaves `expenses` empty, and a
            // banner inside the populated branch would never render — the failure would read as
            // "No expenses match your filters".
            if let err = vm.error {
                ErrorBannerView(message: err) { vm.error = nil }
                    .padding(.horizontal, 12).padding(.bottom, 4)
            }

            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.expenses.isEmpty {
                ContentUnavailableView("No Expenses", systemImage: "receipt",
                    description: Text("No expenses match your filters"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    AdaptiveGrid(minColumnWidth: 360, spacing: 8, uniformHeights: true) {
                        ForEach(vm.expenses) { expense in
                            ExpenseCard(
                                expense: expense,
                                categoryLabel: categoryLabel(vm.categories, expense.categoryId),
                                onEdit: { editingExpense = expense },
                                onDelete: { Task { await vm.deleteExpense(id: expense.id) } },
                                onEditTags: { taggingExpense = expense }
                            )
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)

                    if vm.totalPages > 1 {
                        PaginationRow(currentPage: vm.page, totalPages: vm.totalPages,
                                      onPrev: { vm.prevPage() },
                                      onNext: { vm.nextPage() },
                                      onPage: { vm.goToPage($0) })
                    }
                    Spacer().frame(height: 80)
                }
                .refreshable { await vm.load() }
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = vm.toast {
                Text(msg).font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 80)
                    .onAppear { Task { try? await Task.sleep(for: .seconds(2)); vm.toast = nil } }
            }
        }
    }
}

// MARK: - Expense Card

struct ExpenseCard: View {
    let expense: Expense
    let categoryLabel: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onEditTags: (() -> Void)? = nil
    @State private var showMenu = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.merchant).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 4) {
                    if !categoryLabel.isEmpty { Text(categoryLabel).lineLimit(1); Text("·") }
                    Text(expense.transactionDate.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption).foregroundStyle(.secondary)
                if let comment = expense.comment, !comment.isEmpty {
                    Text(comment).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let sharedBy = expense.sharedByDisplayName {
                    Text("Paid by \(sharedBy)").font(.caption).foregroundStyle(Color.accentColor)
                } else {
                    Text(expense.paymentMethod.displayName).font(.caption).foregroundStyle(.secondary)
                }
                if !expense.allTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(expense.allTags.prefix(4)) { TagChip(tag: $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(expense.amount.formattedINR).font(.subheadline.bold()).foregroundStyle(Color.accentColor)
                Button { showMenu = true } label: {
                    Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary).frame(width: 28, height: 28)
                }
                .confirmationDialog("", isPresented: $showMenu) {
                    Button("Edit") { onEdit() }
                    if let onEditTags { Button("Edit tags") { onEditTags() } }
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
        }
        .padding(12)
        // Fill the cell height so cards line up uniformly in the iPad grid.
        // On iPhone (LazyVStack, unbounded height proposal) this resolves to the
        // card's natural height, leaving the phone layout unchanged.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Filters Panel

private struct FiltersPanel: View {
    let vm: ExpenseListViewModel
    @State private var search = ""
    @State private var showCategoryPicker = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search merchant…", text: $search)
                    .onChange(of: search) { vm.search(search) }
                    .onSubmit { vm.search(search) }
                if !search.isEmpty {
                    Button { search = ""; vm.search("") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8).background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button { showCategoryPicker = true } label: {
                    HStack {
                        Text(vm.selectedCategoryId != nil
                             ? categoryLabel(vm.categories, vm.selectedCategoryId) : "All Categories")
                        .font(.caption).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .padding(8).background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.primary).frame(maxWidth: .infinity)

                Menu {
                    Button("All Methods") { vm.filterMethod(nil) }
                    ForEach(PaymentMethod.allCases) { m in
                        Button(m.displayName) { vm.filterMethod(m) }
                    }
                } label: {
                    HStack {
                        Text(vm.selectedMethod?.displayName ?? "All Methods").font(.caption)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .padding(8).background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.primary).frame(maxWidth: .infinity)
            }

            if vm.hasActiveFilters {
                Button("Clear Filters") { search = ""; vm.clearFilters() }
                    .font(.caption).foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.6))
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(categories: vm.categories, selectedId: vm.selectedCategoryId) {
                vm.filterCategory($0)
            }
        }
        .onAppear { search = vm.searchText }
    }
}

// MARK: - Pagination

private struct PaginationRow: View {
    let currentPage: Int; let totalPages: Int
    let onPrev: () -> Void; let onNext: () -> Void; let onPage: (Int) -> Void
    var visiblePages: [Int] {
        let s = max(1, currentPage - 2); let e = min(s + 4, totalPages); return Array(s...e)
    }
    var body: some View {
        HStack(spacing: 4) {
            Button { onPrev() } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.disabled(currentPage <= 1)
            if (visiblePages.first ?? 1) > 1 {
                pageBtn(1)
                if (visiblePages.first ?? 1) > 2 { Text("…").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(visiblePages, id: \.self) { p in pageBtn(p) }
            if (visiblePages.last ?? totalPages) < totalPages {
                if (visiblePages.last ?? totalPages) < totalPages - 1 { Text("…").font(.caption).foregroundStyle(.secondary) }
                pageBtn(totalPages)
            }
            Button { onNext() } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }.disabled(currentPage >= totalPages)
        }
        .padding(.vertical, 8)
    }
    private func pageBtn(_ p: Int) -> some View {
        Button { onPage(p) } label: {
            Text("\(p)").font(.caption.bold()).frame(width: 32, height: 32)
                .background(p == currentPage ? Color.accentColor : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(p == currentPage ? .white : .primary)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String; let selected: Bool; let action: () -> Void
    init(_ label: String, selected: Bool, action: @escaping () -> Void) {
        self.label = label; self.selected = selected; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(label).font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Category Picker Sheet (drill-down style, matches Android)

struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    let selectedId: String?
    let onSelect: (String?) -> Void

    @State private var stack: [Category] = []

    private var currentItems: [Category] { stack.last?.children ?? categories }

    var body: some View {
        NavigationStack {
            List {
                // When drilled in: offer "select this level" row
                if let current = stack.last {
                    Button {
                        onSelect(current.id); dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(current.icon ?? "") \(current.name)".trimmingCharacters(in: .whitespaces))
                                    .font(.subheadline.bold())
                                Text("Select without sub-category").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedId == current.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                ForEach(currentItems) { node in
                    let isLeaf = node.children.isEmpty
                    Button {
                        if isLeaf { onSelect(node.id); dismiss() }
                        else { stack.append(node) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(node.icon ?? "") \(node.name)".trimmingCharacters(in: .whitespaces))
                                    .font(.subheadline)
                                if !isLeaf {
                                    Text("\(node.children.count) sub-categories")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedId == node.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            } else if !isLeaf {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle(stack.last.map { "\($0.icon ?? "") \($0.name)".trimmingCharacters(in: .whitespaces) } ?? "Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if stack.isEmpty {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button { stack.removeLast() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if selectedId != nil {
                        Button("Clear") { onSelect(nil); dismiss() }
                    }
                }
            }
        }
        // Breadcrumb path when deep
        .safeAreaInset(edge: .top, spacing: 0) {
            if stack.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(stack.enumerated()), id: \.offset) { idx, crumb in
                            Button {
                                stack = Array(stack.prefix(idx + 1))
                            } label: {
                                Text("\(crumb.icon ?? "") \(crumb.name)".trimmingCharacters(in: .whitespaces))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if idx < stack.count - 1 {
                                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
                .background(Color(.systemGray6))
            }
        }
    }
}

// MARK: - Add Expense Sheet (matches Android layout)

struct AddExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    let accounts: [PaymentAccount]
    let familyMembers: [FamilyMember]
    let onSave: (Double, String, PaymentMethod, Date, String?, String?, String?, String?) -> Void
    var onSettle: ((Double, PaymentMethod, String, Date, String?, String?) -> Void)? = nil

    @State private var amountText = ""
    @State private var merchant = ""
    @State private var method: PaymentMethod = .upi
    @State private var date = Date()
    @State private var time = Date()
    @State private var comment = ""
    @State private var categoryId: String? = nil
    @State private var accountId: String? = nil
    @State private var isForSomeone = false
    @State private var isRepayment = false
    @State private var selectedMemberId: String? = nil
    @State private var showCategorySheet = false

    private var filteredAccounts: [PaymentAccount] {
        let allowed: [AccountType] = switch method {
        case .upi, .netBanking: [.savings, .current, .wallet]
        case .card: [.creditCard, .debitCard]
        default: []
        }
        return allowed.isEmpty ? accounts.filter(\.isActive)
                               : accounts.filter { $0.isActive && allowed.contains($0.accountType) }
    }

    private var amountValid: Bool { (Double(amountText) ?? 0) > 0 }
    private var merchantRequired: Bool { !(isForSomeone && isRepayment) }
    private var canSave: Bool {
        amountValid && (!merchantRequired || !merchant.isEmpty) && (!isForSomeone || selectedMemberId != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Self / For Someone — only when family members exist
                    if !familyMembers.isEmpty {
                        Picker("", selection: $isForSomeone) {
                            Text("Self").tag(false)
                            Text("For Someone").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: isForSomeone) {
                            if !isForSomeone { isRepayment = false; selectedMemberId = nil }
                        }

                        if isForSomeone {
                            outlinedPicker(
                                label: "Paying for *",
                                value: familyMembers.first(where: { $0.userId == selectedMemberId })?.displayName ?? ""
                            ) {
                                ForEach(familyMembers) { m in
                                    Button(m.displayName) { selectedMemberId = m.userId }
                                }
                            }

                            Picker("", selection: $isRepayment) {
                                Text("Regular").tag(false)
                                Text("Repayment").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Amount
                    outlinedField("Amount (₹)", text: $amountText, keyboard: .decimalPad,
                                  isError: !amountText.isEmpty && !amountValid)

                    // Merchant (hidden in repayment)
                    if merchantRequired {
                        outlinedField("Merchant", text: $merchant)
                    }

                    // Date + Time
                    HStack(spacing: 8) {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .padding(12)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .padding(12)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                    }

                    // Payment Method
                    outlinedPicker(label: "Payment Method", value: method.displayName) {
                        ForEach(PaymentMethod.allCases) { m in
                            Button(m.displayName) { method = m; accountId = nil }
                        }
                    }

                    // Account
                    if !filteredAccounts.isEmpty {
                        outlinedPicker(
                            label: "Account",
                            value: filteredAccounts.first(where: { $0.id == accountId })
                                .map { $0.last4 != nil ? "\($0.name) ••\($0.last4!)" : $0.name } ?? "None"
                        ) {
                            Button("None") { accountId = nil }
                            ForEach(filteredAccounts) { a in
                                Button {
                                    accountId = a.id
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(a.name)
                                        if let bank = a.bank, let last4 = a.last4 {
                                            Text("\(bank) ••\(last4)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Category (hidden when paying for someone)
                    if !isForSomeone {
                        Button { showCategorySheet = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Category").font(.caption).foregroundStyle(.secondary)
                                    Text(categoryId != nil ? categoryLabel(categories, categoryId) : "None")
                                        .font(.subheadline).foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                        }
                    }

                    // Comment
                    outlinedField("Comment", text: $comment)

                    // Save button
                    Button {
                        guard let amount = Double(amountText), amount > 0 else { return }
                        let when = combinedDateTime()
                        if isForSomeone && isRepayment, let memberId = selectedMemberId, let onSettle {
                            onSettle(amount, method, memberId, when, accountId, comment.isEmpty ? nil : comment)
                        } else {
                            onSave(amount, merchant, method, when,
                                   comment.isEmpty ? nil : comment,
                                   isForSomeone ? nil : categoryId,
                                   accountId,
                                   isForSomeone ? selectedMemberId : nil)
                        }
                        dismiss()
                    } label: {
                        Text(isForSomeone && isRepayment ? "Settle" : isForSomeone ? "Send to Family" : "Add Expense")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(canSave ? Color.accentColor : Color(.systemGray4))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!canSave)
                }
                .padding(16)
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showCategorySheet) {
                CategoryPickerSheet(categories: categories, selectedId: categoryId) { categoryId = $0 }
            }
        }
    }

    private func combinedDateTime() -> Date {
        let cal = Calendar.current
        let day = cal.dateComponents([.year, .month, .day], from: date)
        let time = cal.dateComponents([.hour, .minute], from: self.time)
        var merged = DateComponents()
        merged.year = day.year; merged.month = day.month; merged.day = day.day
        merged.hour = time.hour; merged.minute = time.minute
        return cal.date(from: merged) ?? date
    }

    // Outlined text field matching Android's OutlinedTextField
    private func outlinedField(_ label: String, text: Binding<String>,
                                keyboard: UIKeyboardType = .default,
                                isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(isError ? .red : .secondary).padding(.leading, 4)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(isError ? Color.red : Color(.systemGray3), lineWidth: 1))
        }
    }

    // Outlined menu picker matching Android's ExposedDropdownMenuBox
    private func outlinedPicker<Content: View>(label: String, value: String,
                                               @ViewBuilder items: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
            Menu {
                items()
            } label: {
                HStack {
                    Text(value.isEmpty ? label : value).foregroundStyle(value.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundStyle(.secondary)
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
            }
        }
    }
}

// MARK: - Edit Expense Sheet

struct EditExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    let categories: [Category]
    let onSave: (String, String?, String?, PaymentMethod) -> Void

    @State private var merchant: String
    @State private var comment: String
    @State private var selectedCategoryId: String?
    @State private var selectedMethod: PaymentMethod
    @State private var showCategorySheet = false

    init(expense: Expense, categories: [Category],
         onSave: @escaping (String, String?, String?, PaymentMethod) -> Void) {
        self.expense = expense; self.categories = categories; self.onSave = onSave
        _merchant = State(initialValue: expense.merchant)
        _comment = State(initialValue: expense.comment ?? "")
        _selectedCategoryId = State(initialValue: expense.categoryId)
        _selectedMethod = State(initialValue: expense.paymentMethod)
    }

    var isShared: Bool { expense.sharedByUserId != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Subtitle
                    HStack {
                        Text("\(expense.amount.formattedINR) · \(expense.transactionDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }

                    // Shared lock notice
                    if isShared {
                        HStack(spacing: 6) {
                            Image(systemName: "lock").font(.caption)
                            Text("Paid by \(expense.sharedByDisplayName ?? "") — only category and comment can be edited.")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))

                        Text("\(expense.merchant) · \(expense.paymentMethod.displayName)")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        outlinedField("Merchant", text: $merchant)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Payment Method").font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                            Menu {
                                ForEach(PaymentMethod.allCases) { m in
                                    Button(m.displayName) { selectedMethod = m }
                                }
                            } label: {
                                HStack {
                                    Text(selectedMethod.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.down").foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                            }
                        }
                    }

                    outlinedField("Comment", text: $comment)

                    Button { showCategorySheet = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Category").font(.caption).foregroundStyle(.secondary)
                                Text(selectedCategoryId != nil ? categoryLabel(categories, selectedCategoryId) : "None")
                                    .font(.subheadline).foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                    }

                    Button {
                        onSave(merchant, comment.isEmpty ? nil : comment, selectedCategoryId, selectedMethod)
                        dismiss()
                    } label: {
                        Text("Save").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.accentColor).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!isShared && merchant.isEmpty)
                }
                .padding(16)
            }
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showCategorySheet) {
                CategoryPickerSheet(categories: categories, selectedId: selectedCategoryId) { selectedCategoryId = $0 }
            }
        }
    }

    private func outlinedField(_ label: String, text: Binding<String>,
                                keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
            TextField(label, text: text).keyboardType(keyboard)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
        }
    }
}

// MARK: - Helpers

func categoryLabel(_ categories: [Category], _ id: String?) -> String {
    guard let id else { return "" }
    func findPath(in nodes: [Category], target: String) -> [Category]? {
        for node in nodes {
            if node.id == target { return [node] }
            if let sub = findPath(in: node.children, target: target) { return [node] + sub }
        }
        return nil
    }
    for root in categories {
        if root.id == id { return "\(root.icon ?? "") \(root.name)".trimmingCharacters(in: .whitespaces) }
        if let path = findPath(in: root.children, target: id) {
            let rootLabel = "\(root.icon ?? "") \(root.name)".trimmingCharacters(in: .whitespaces)
            return ([rootLabel] + path.map(\.name)).joined(separator: "  ›  ")
        }
    }
    return ""
}
