import SwiftUI

// Observable class so async mutations propagate correctly to the UI
@Observable
@MainActor
final class MerchantRulesViewModel: AuthedViewModel {
    var rules: [MerchantRule] = []
    var categories: [Category] = []
    var isLoading = false
    var isSyncing = false
    var isApplying = false
    var isAdvancedUser = false
    var toast: String?
    var error: String?

    private let ruleService: MerchantRuleService
    private let catService: CategoryService
    private let expenseService: ExpenseService
    private let userService: UserService

    init(auth: AuthState) {
        ruleService = MerchantRuleService(auth: auth)
        catService = CategoryService(auth: auth)
        expenseService = ExpenseService(auth: auth)
        userService = UserService(auth: auth)
    }

    func load() async {
        isLoading = true
        error = nil
        async let r = ruleService.getRules()
        async let c = catService.getCategories()
        async let p = userService.getProfile()
        do {
            let (loadedRules, loadedCategories) = try await (r, c)
            rules = loadedRules
            categories = loadedCategories
        } catch {
            self.error = error.localizedDescription
        }
        // The profile only decides whether AND/OR matching is offered — falling back to the plain
        // mode is a fine degradation and not worth failing the whole screen over.
        isAdvancedUser = (try? await p)?.isAdvancedUser ?? false
        isLoading = false
    }

    func sync() async {
        isSyncing = true
        error = nil
        do {
            rules = try await ruleService.getRules()
            toast = "Synced \(rules.count) rule\(rules.count == 1 ? "" : "s") from server"
        } catch {
            self.error = error.localizedDescription
        }
        isSyncing = false
    }

    func applyToDrafts() async {
        isApplying = true
        do {
            try await expenseService.exposeApplyRules()
            toast = "Rules applied to drafts"
        } catch {
            self.toast = "Apply failed: \(error.localizedDescription)"
        }
        isApplying = false
    }

    func createRule(match: String, display: String, min: Double?, max: Double?,
                    catId: String?, autoSubmit: Bool, matchMode: String, andApply: Bool = false) async {
        let req = MerchantRuleRequest(matchText: match, displayName: display.isEmpty ? nil : display,
                                      minAmount: min, maxAmount: max,
                                      categoryId: catId, autoSubmit: autoSubmit, matchMode: matchMode)
        do {
            try await ruleService.createRule(req)
            toast = "Rule created"
            await load()
            if andApply { await applyToDrafts() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateRule(id: String, match: String, display: String, min: Double?, max: Double?,
                    catId: String?, autoSubmit: Bool, matchMode: String, andApply: Bool = false) async {
        let req = MerchantRuleRequest(matchText: match, displayName: display.isEmpty ? nil : display,
                                      minAmount: min, maxAmount: max,
                                      categoryId: catId, autoSubmit: autoSubmit, matchMode: matchMode)
        do {
            try await ruleService.updateRule(id: id, req: req)
            toast = "Rule updated"
            await load()
            if andApply { await applyToDrafts() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteRule(id: String) async {
        do {
            try await ruleService.deleteRule(id: id)
            rules.removeAll { $0.id == id }
            toast = "Rule deleted"
        } catch {
            // Don't drop the row locally — it's still on the server.
            self.error = error.localizedDescription
        }
    }
}

// MARK: - View

struct MerchantRulesView: View {
    @Environment(AuthState.self) private var authState
    @State private var vm: MerchantRulesViewModel?
    @State private var showDialog = false
    @State private var editingRule: MerchantRule?

    var body: some View {
        Group {
            if let vm { content(vm: vm) }
            else { ProgressView() }
        }
        .navigationTitle("Merchant Rules")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let (model, isNew) = ViewModelStore.shared.model(MerchantRulesViewModel.self, auth: authState)
            vm = model
            if isNew { await model.load() }
        }
        .sheet(isPresented: $showDialog) {
            if let vm {
                RuleDialog(rule: editingRule, categories: vm.categories, isAdvancedUser: vm.isAdvancedUser) { match, display, min, max, catId, autoSubmit, matchMode, andApply in
                    if let existing = editingRule {
                        Task { await vm.updateRule(id: existing.id, match: match, display: display,
                                                   min: min, max: max, catId: catId, autoSubmit: autoSubmit,
                                                   matchMode: matchMode, andApply: andApply) }
                    } else {
                        Task { await vm.createRule(match: match, display: display,
                                                   min: min, max: max, catId: catId, autoSubmit: autoSubmit,
                                                   matchMode: matchMode, andApply: andApply) }
                    }
                    editingRule = nil
                }
            }
        }
    }

    @ViewBuilder
    private func content(vm: MerchantRulesViewModel) -> some View {
        Group {
            if vm.isLoading { ProgressView() }
            else if vm.rules.isEmpty { emptyState }
            else { ruleList(vm: vm) }
        }
        .toolbar { toolbarItems(vm: vm) }
        .overlay(alignment: .bottomTrailing) { fab }
        .overlay(alignment: .bottom) {
            if let msg = vm.toast {
                Text(msg).font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 80)
                    .onAppear { Task { try? await Task.sleep(for: .seconds(2)); vm.toast = nil } }
            }
        }
        .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wand.and.stars").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No merchant rules yet").font(.title3).foregroundStyle(.secondary)
            Text("Rules rename, categorize, or auto-submit merchants during email scan.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
    }

    private func ruleList(vm: MerchantRulesViewModel) -> some View {
        ScrollView {
            AdaptiveGrid(minColumnWidth: 360, spacing: 8) {
                ForEach(vm.rules) { rule in
                    MerchantRuleCard(
                        rule: rule,
                        categories: vm.categories,
                        onEdit: { editingRule = rule; showDialog = true },
                        onDelete: { Task { await vm.deleteRule(id: rule.id) } }
                    )
                }
            }
            .padding(.horizontal, 16).padding(.top, 12)

            Spacer().frame(height: 80)
        }
        .refreshable { await vm.load() }
    }

    @ToolbarContentBuilder
    private func toolbarItems(vm: MerchantRulesViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if !vm.rules.isEmpty {
                Text("\(vm.rules.count) rule\(vm.rules.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await vm.applyToDrafts() } } label: {
                if vm.isApplying { ProgressView().scaleEffect(0.7) }
                else { Image(systemName: "play.fill") }
            }
            .disabled(vm.isApplying || vm.rules.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await vm.sync() } } label: {
                if vm.isSyncing { ProgressView().scaleEffect(0.7) }
                else { Image(systemName: "arrow.clockwise") }
            }
            .disabled(vm.isSyncing)
        }
    }

    private var fab: some View {
        Button { editingRule = nil; showDialog = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Add Rule").font(.subheadline.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Color.accentColor, in: Capsule())
            .shadow(radius: 4)
        }
        .padding(20)
    }
}

// MARK: - Rule Card

private struct MerchantRuleCard: View {
    let rule: MerchantRule
    let categories: [Category]
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    private var catLabel: String { categoryLabel(categories, rule.categoryId) }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                if let displayName = rule.displayName, !displayName.isEmpty {
                    Text(displayName).font(.subheadline.bold()).lineLimit(1)
                } else {
                    Text("— no rename").font(.subheadline.italic()).foregroundStyle(.secondary).lineLimit(1)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text(rule.matchText)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)

                        if rule.matchMode == "All" || rule.matchMode == "Any" {
                            Text(rule.matchMode == "All" ? "AND" : "OR").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundStyle(.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if !catLabel.isEmpty {
                            Text(catLabel).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if rule.minAmount != nil || rule.maxAmount != nil {
                            Text(amountLabel).font(.caption2).foregroundStyle(.secondary)
                        }

                        if rule.autoSubmit {
                            Text("Auto-submit").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onEdit) {
                Image(systemName: "pencil").font(.system(size: 15))
                    .frame(width: 34, height: 34).foregroundStyle(Color.accentColor)
            }
            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash").font(.system(size: 15))
                    .frame(width: 34, height: 34).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .confirmationDialog("Delete rule?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete \"\(rule.matchText)\"", role: .destructive) { onDelete() }
        } message: {
            if let displayName = rule.displayName, !displayName.isEmpty {
                Text("\"\(rule.matchText)\" → \"\(displayName)\" will be removed.")
            } else {
                Text("\"\(rule.matchText)\" will be removed.")
            }
        }
    }

    private var amountLabel: String {
        switch (rule.minAmount, rule.maxAmount) {
        case let (min?, max?): return "₹\(Int(min))–₹\(Int(max))"
        case let (min?, nil):  return "≥₹\(Int(min))"
        case let (nil, max?):  return "≤₹\(Int(max))"
        default: return ""
        }
    }
}

// MARK: - Rule Dialog

private struct RuleDialog: View {
    @Environment(\.dismiss) private var dismiss
    let rule: MerchantRule?
    let categories: [Category]
    let isAdvancedUser: Bool
    let onSave: (String, String, Double?, Double?, String?, Bool, String, Bool) -> Void

    @State private var matchText: String
    @State private var displayName: String
    @State private var displayNameEdited: Bool
    @State private var rename: Bool
    @State private var matchMode: String
    @State private var minAmount = ""
    @State private var maxAmount = ""
    @State private var categoryId: String?
    @State private var autoSubmit: Bool
    @State private var showCategoryPicker = false

    init(rule: MerchantRule?, categories: [Category], isAdvancedUser: Bool,
         onSave: @escaping (String, String, Double?, Double?, String?, Bool, String, Bool) -> Void) {
        self.rule = rule; self.categories = categories; self.isAdvancedUser = isAdvancedUser; self.onSave = onSave
        _matchText   = State(initialValue: rule?.matchText ?? "")
        _displayName = State(initialValue: rule?.displayName ?? "")
        _displayNameEdited = State(initialValue: rule != nil)
        _rename      = State(initialValue: rule.map { !($0.displayName ?? "").isEmpty } ?? true)
        _matchMode   = State(initialValue: rule?.matchMode ?? "Contains")
        _minAmount   = State(initialValue: rule?.minAmount.map { String(Int($0)) } ?? "")
        _maxAmount   = State(initialValue: rule?.maxAmount.map { String(Int($0)) } ?? "")
        _categoryId  = State(initialValue: rule?.categoryId)
        _autoSubmit  = State(initialValue: rule?.autoSubmit ?? false)
    }

    private var isAdvancedMode: Bool { isAdvancedUser && matchMode != "Contains" }

    private var canSave: Bool {
        let hasMatch = !matchText.trimmingCharacters(in: .whitespaces).isEmpty
        let hasName = !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        return hasMatch && (!rename || hasName)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isAdvancedUser {
                    Section {
                        Picker("Match", selection: $matchMode) {
                            Text("Contains").tag("Contains")
                            Text("All words (AND)").tag("All")
                            Text("Any word (OR)").tag("Any")
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isAdvancedMode ? "Terms (comma-separated)" : "When merchant contains")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField(isAdvancedMode ? "e.g. amazon, prime" : "e.g. BLINKIT", text: $matchText)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: matchText) {
                                if rename && !displayNameEdited { displayName = matchText }
                            }
                        Text(isAdvancedMode ? "Case-insensitive" : "Case-insensitive substring match")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    Toggle(isOn: $rename) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rename merchant").font(.subheadline.bold())
                            Text("Turn off to only assign a category and/or auto-submit")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if rename {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rename to").font(.caption).foregroundStyle(.secondary)
                            TextField("e.g. Blinkit Groceries", text: $displayName)
                                .onChange(of: displayName) { displayNameEdited = true }
                        }
                    }
                }

                Section("Category (optional)") {
                    Button { showCategoryPicker = true } label: {
                        HStack {
                            Text(categoryId != nil ? categoryLabel(categories, categoryId) : "None")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $autoSubmit) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-submit").font(.subheadline.bold())
                            Text("Skip draft queue — submit immediately on match")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Amount Filter (optional)") {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Min ₹").font(.caption).foregroundStyle(.secondary)
                            TextField("Any", text: $minAmount).keyboardType(.decimalPad)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max ₹").font(.caption).foregroundStyle(.secondary)
                            TextField("Any", text: $maxAmount).keyboardType(.decimalPad)
                        }
                    }
                }
            }
            .navigationTitle(rule != nil ? "Edit Rule" : "Add Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save & Run") { save(andApply: true) }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(andApply: false) }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(categories: categories, selectedId: categoryId) { categoryId = $0 }
            }
        }
    }

    private func save(andApply: Bool) {
        onSave(matchText.trimmingCharacters(in: .whitespaces),
               rename ? displayName.trimmingCharacters(in: .whitespaces) : "",
               Double(minAmount), Double(maxAmount),
               categoryId, autoSubmit,
               isAdvancedUser ? matchMode : "Contains",
               andApply)
        dismiss()
    }
}
