import SwiftUI

struct BudgetsView: View {
    @Environment(AuthState.self) private var authState
    @State private var vm: BudgetsViewModel?
    @State private var editingBudget: BudgetEditTarget?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm { budgetContent(vm: vm) }
                else { ProgressView() }
            }
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let vm, vm.selectedTab == 0 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { showSettings = true } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let vm { Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") } }
                }
            }
        }
        .task {
            let (model, isNew) = ViewModelStore.shared.model(BudgetsViewModel.self, auth: authState)
            vm = model
            if isNew { await model.load() }
        }
        .sheet(item: $editingBudget) { target in
            if let vm {
                SetBudgetSheet(target: target, vm: vm) {
                    editingBudget = nil
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            if let vm { BudgetSettingsSheet(vm: vm) }
        }
    }

    @ViewBuilder
    private func budgetContent(vm: BudgetsViewModel) -> some View {
        VStack(spacing: 0) {
            // Tab
            Picker("", selection: Bindable(vm).selectedTab) {
                Text("Monthly").tag(0)
                Text("Trips and Events").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            // Cycle info strip (monthly only)
            if vm.selectedTab == 0 {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.caption2).foregroundStyle(Color.accentColor)
                    Text("Cycle from day \(vm.cycleDay)")
                        .font(.caption).foregroundStyle(Color.accentColor)
                    Spacer()
                    Button("Edit") { showSettings = true }.font(.caption)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08))

                PeriodNavBar(
                    period: Binding(get: { vm.period }, set: { vm.setPeriod($0) }),
                    showModeToggle: false,
                    // A default applies to every month, so planning ahead is meaningful here —
                    // unlike every other page, which has no data past today.
                    allowFuture: true,
                    showJumpToPresent: true
                )
                .padding(.horizontal, 16).padding(.top, 6)

                // Always offered, including on a past month — Defaults is month-independent and
                // is the only thing still editable there.
                Picker("", selection: Bindable(vm).viewMode) {
                    Text("This month").tag(BudgetViewMode.month)
                    Text("Defaults").tag(BudgetViewMode.defaults)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 6)

                if vm.viewMode == .defaults {
                    Text("Editing defaults — applies to every month with no amount of its own. Recorded months keep theirs.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 4)
                }
            }

            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.error {
                ErrorBannerView(message: err) { vm.error = nil }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if vm.selectedTab == 0 {
                            monthlyContent(vm: vm)
                        } else {
                            tripContent(vm: vm)
                        }
                        Spacer().frame(height: 80)
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }
                .refreshable { await vm.load() }
            }
        }
    }

    // MARK: - Monthly tab

    @ViewBuilder
    private func monthlyContent(vm: BudgetsViewModel) -> some View {
        if vm.monthlyCategories.isEmpty {
            ContentUnavailableView("No categories yet", systemImage: "tag")
        } else {
            // Overall budget card
            let overall = vm.budgetMap[nil]
            OverallBudgetCard(
                vm: vm,
                budget: overall,
                onTap: {
                    guard vm.rowEditable(overall), !vm.rowNotSet(overall) else { return }
                    editingBudget = makeMonthlyEditTarget(vm: vm, categoryId: nil, categoryName: "Total Budget", existing: overall)
                }
            )

            // L1 accordion cards
            AdaptiveGrid(minColumnWidth: 380, spacing: 8) {
                ForEach(vm.monthlyCategories) { l1 in
                    L1BudgetCard(
                        l1: l1,
                        vm: vm,
                        onTap: { catId, name, existing in
                            guard vm.rowEditable(existing), !vm.rowNotSet(existing) else { return }
                            editingBudget = makeMonthlyEditTarget(vm: vm, categoryId: catId, categoryName: name, existing: existing)
                        }
                    )
                }
            }
        }
    }

    private func makeMonthlyEditTarget(vm: BudgetsViewModel, categoryId: String?, categoryName: String, existing: Budget?) -> BudgetEditTarget {
        let isMonthMode = vm.viewMode == .month
        return BudgetEditTarget(
            categoryId: categoryId, categoryName: categoryName, existing: existing, isTrip: false,
            isMonthMode: isMonthMode && existing != nil,
            initialAmount: isMonthMode ? existing?.cycleBaseAmount : existing?.defaultAmount,
            maxAllowed: vm.maxAllowed(for: categoryId, isTrip: false),
            canDelete: vm.viewMode == .defaults
        )
    }

    // MARK: - Trip tab

    @ViewBuilder
    private func tripContent(vm: BudgetsViewModel) -> some View {
        if vm.tripEntries.isEmpty {
            ContentUnavailableView("No trips or events yet",
                systemImage: "airplane",
                description: Text("Add a subcategory under a \"Trips and Events\" bucket in Categories — the one under Household is shared, one under Personal is yours alone"))
        } else {
            AdaptiveGrid(minColumnWidth: 380, spacing: 8) {
                ForEach(vm.tripEntries) { entry in
                    TripL2Card(
                        l2: entry.category,
                        isShared: entry.isShared,
                        vm: vm,
                        onTapL2: { catId, name, existing in
                            editingBudget = BudgetEditTarget(
                                categoryId: catId, categoryName: name, existing: existing, isTrip: true,
                                initialAmount: existing?.defaultAmount,
                                maxAllowed: vm.maxAllowed(for: catId, isTrip: true)
                            )
                        },
                        // A sub-category of a trip is itself a date-range budget — it inherits the
                        // trip's range rather than picking its own. Sending it as monthly would
                        // hit the server's "excluded from budget planning" guard, since the whole
                        // Trips subtree is excluded from monthly planning.
                        onTapL3: { catId, name, existing, parentBudget in
                            editingBudget = BudgetEditTarget(
                                categoryId: catId, categoryName: name, existing: existing, isTrip: true,
                                inheritsDates: true,
                                inheritedStart: parentBudget?.startDate,
                                inheritedEnd: parentBudget?.endDate,
                                initialAmount: existing?.defaultAmount,
                                maxAllowed: vm.maxAllowed(for: catId, isTrip: true)
                            )
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Edit target

struct BudgetEditTarget: Identifiable {
    var id: String { categoryId ?? "overall" }
    let categoryId: String?
    let categoryName: String
    let existing: Budget?
    let isTrip: Bool
    /// A trip sub-category: still a date-range budget, but the range comes from its parent trip
    /// rather than a picker of its own.
    var inheritsDates: Bool = false
    var inheritedStart: Date? = nil
    var inheritedEnd: Date? = nil
    var isMonthMode: Bool = false
    var initialAmount: Double? = nil
    var maxAllowed: Double? = nil
    var canDelete: Bool = true
}

// MARK: - Overall Budget Card

private struct OverallBudgetCard: View {
    let vm: BudgetsViewModel
    let budget: Budget?
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#3b82f6").opacity(0.18))
                        .frame(width: 36, height: 36)
                    Text("💰")
                }
                Text("Total Budget").font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)
                BudgetCellButton(vm: vm, budget: budget, notSet: vm.rowNotSet(budget),
                                 disabled: !vm.rowEditable(budget), onTap: onTap)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(hex: "#3b82f6").opacity(0.08))

            if let b = budget, vm.rowShowsBar(b) {
                Divider()
                VStack(spacing: 4) {
                    progressSection(b)
                    let allocated = vm.monthlyCategories.compactMap { vm.budgetMap[$0.id]?.effectiveAmount }.reduce(0, +)
                    let unalloc = b.effectiveAmount - allocated
                    if allocated > 0 && abs(unalloc) > 0.01 {
                        HStack {
                            Text("\(unalloc.shortINR) unallocated")
                                .font(.caption2)
                                .foregroundStyle(unalloc < 0 ? .red : .secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - L1 Accordion Card

private struct L1BudgetCard: View {
    let l1: Category
    let vm: BudgetsViewModel
    let onTap: (String?, String, Budget?) -> Void
    @State private var expanded = false

    private var budget: Budget? { vm.budgetMap[l1.id] }
    private var accentColor: Color { l1.color.map { Color.fromHex($0) } ?? Color(hex: "#3b82f6") }
    private var pastReadOnly: Bool { !vm.rowEditable(budget) }
    private var notSet: Bool { vm.rowNotSet(budget) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    if let icon = l1.icon, !icon.isEmpty {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(accentColor.opacity(0.18))
                                .frame(width: 36, height: 36)
                            Text(icon).font(.body)
                        }
                    }
                    Text(l1.name).font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)

                    if !l1.children.isEmpty {
                        Text("\(l1.children.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if vm.rowShowsRawSpend(budget) && vm.spentRecursive(l1) > 0 {
                        Text(vm.spentRecursive(l1).shortINR).font(.caption2).foregroundStyle(.secondary)
                    }
                    BudgetCellButton(vm: vm, budget: budget, notSet: notSet, disabled: pastReadOnly) { onTap(l1.id, l1.name, budget) }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(accentColor.opacity(0.08))
            }
            .buttonStyle(.plain)

            // Progress
            if let b = budget, vm.rowShowsBar(b) {
                Divider()
                VStack(spacing: 4) {
                    progressSection(b)
                    let allocated = l1.children.compactMap { vm.budgetMap[$0.id]?.effectiveAmount }.reduce(0, +)
                    let unalloc = b.effectiveAmount - allocated
                    if allocated > 0 && abs(unalloc) > 0.01 {
                        HStack {
                            Text("\(unalloc.shortINR) unallocated")
                                .font(.caption2)
                                .foregroundStyle(unalloc < 0 ? .red : .secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }

            // Children
            if expanded {
                if l1.children.isEmpty {
                    Divider()
                    Text("No subcategories").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(l1.children) { l2 in
                        Divider()
                        L2BudgetRow(l2: l2, vm: vm, onTap: { onTap(l2.id, l2.name, vm.budgetMap[l2.id]) },
                                    onTapL3: { l3 in onTap(l3.id, l3.name, vm.budgetMap[l3.id]) })
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - L2 Row

private struct L2BudgetRow: View {
    let l2: Category
    let vm: BudgetsViewModel
    let onTap: () -> Void
    let onTapL3: (Category) -> Void

    private var budget: Budget? { vm.budgetMap[l2.id] }
    private var spent: Double { vm.categorySpending[l2.id] ?? 0 }
    private var pastReadOnly: Bool { !vm.rowEditable(budget) }
    private var notSet: Bool { vm.rowNotSet(budget) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 22)
                if let icon = l2.icon, !icon.isEmpty { Text(icon).font(.caption) }
                Text(l2.name).font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)
                if vm.rowShowsRawSpend(budget) && spent > 0 { Text(spent.shortINR).font(.caption2).foregroundStyle(.secondary) }
                BudgetCellButton(vm: vm, budget: budget, notSet: notSet, disabled: pastReadOnly, onTap: onTap)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            if let b = budget, vm.rowShowsBar(b) {
                progressSection(b).padding(.horizontal, CGFloat(14 + 22)).padding(.bottom, 6)
            }

            // L3 rows
            ForEach(l2.children) { l3 in
                let l3b = vm.budgetMap[l3.id]
                let l3s = vm.categorySpending[l3.id] ?? 0
                let l3ReadOnly = !vm.rowEditable(l3b)
                let l3NotSet = vm.rowNotSet(l3b)
                Divider().padding(.leading, 36)
                HStack(spacing: 8) {
                    Color.clear.frame(width: 36)
                    Text(l3.name).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    if vm.rowShowsRawSpend(l3b) && l3s > 0 { Text(l3s.shortINR).font(.caption2).foregroundStyle(.secondary) }
                    BudgetCellButton(vm: vm, budget: l3b, notSet: l3NotSet, disabled: l3ReadOnly) { onTapL3(l3) }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                if let b3 = l3b, vm.rowShowsBar(b3) {
                    ProgressBarView(spent: b3.spent, total: b3.effectiveAmount, showLabel: false)
                        .padding(.horizontal, CGFloat(14 + 36)).padding(.bottom, 4)
                }
            }
        }
    }
}

// MARK: - Trip L2 Card

private struct TripL2Card: View {
    let l2: Category
    let isShared: Bool
    let vm: BudgetsViewModel
    let onTapL2: (String, String, Budget?) -> Void
    let onTapL3: (String, String, Budget?, Budget?) -> Void
    @State private var expanded = false

    private var budget: Budget? { vm.tripBudgetMap[l2.id] }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#60a5fa").opacity(0.18)).frame(width: 36, height: 36)
                        Text(l2.icon ?? "✈️")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l2.name).font(.subheadline.bold())
                        if let b = budget, let start = b.startDate, let end = b.endDate {
                            Text("\(start.shortDateString) – \(end.shortDateString)")
                                .font(.caption2).foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    sharedBadge
                    BudgetCellButton(vm: vm, budget: budget) { onTapL2(l2.id, l2.name, budget) }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(hex: "#60a5fa").opacity(0.08))
            }
            .buttonStyle(.plain)

            if let b = budget {
                Divider()
                progressSection(b).padding(.horizontal, 14).padding(.vertical, 8)
            }

            if expanded {
                if l2.children.isEmpty {
                    Divider()
                    Text("No sub-categories").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(l2.children) { l3 in
                        let l3b = vm.tripBudgetMap[l3.id]
                        let l3s = budget?.categorySpending?[l3.id] ?? 0
                        Divider()
                        HStack(spacing: 8) {
                            Color.clear.frame(width: 22)
                            Text(l3.name).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            if l3s > 0 { Text(l3s.shortINR).font(.caption2).foregroundStyle(.secondary) }
                            BudgetCellButton(vm: vm, budget: l3b) { onTapL3(l3.id, l3.name, l3b, budget) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if let b3 = l3b {
                            ProgressBarView(spent: b3.spent, total: b3.effectiveAmount, showLabel: false)
                                .padding(.horizontal, CGFloat(14 + 22)).padding(.bottom, 4)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // Who this trip's spending covers — the shared bucket pools the whole family,
    // a personal one only its owner.
    private var sharedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: isShared ? "person.3.fill" : "person.fill")
            Text(isShared ? "Family" : "Personal")
        }
        .font(.caption2)
        .foregroundStyle(isShared ? Color.accentColor : .secondary)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(
            (isShared ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: 4)
        )
    }
}

// MARK: - Set Budget Sheet

struct SetBudgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: BudgetEditTarget
    let vm: BudgetsViewModel
    let onDone: () -> Void

    @State private var amountStr: String
    @State private var startDate: Date
    @State private var endDate: Date

    init(target: BudgetEditTarget, vm: BudgetsViewModel, onDone: @escaping () -> Void) {
        self.target = target; self.vm = vm; self.onDone = onDone
        let seed = target.initialAmount ?? target.existing?.defaultAmount
        _amountStr = State(initialValue: seed.map { String(format: "%.0f", $0) } ?? "")
        _startDate = State(initialValue: target.existing?.startDate ?? target.inheritedStart ?? Date.startOfThisMonth)
        _endDate   = State(initialValue: target.existing?.endDate ?? target.inheritedEnd
                           ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
    }

    /// Nil whenever Save must stay inactive, so a zero or unparseable amount reads as disabled
    /// rather than as a button that does nothing.
    private var amountValue: Double? {
        guard let amount = Double(amountStr), amount > 0 else { return nil }
        return amount
    }

    private var exceedsMax: Bool {
        guard let max = target.maxAllowed, let amount = amountValue else { return false }
        return amount > max
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.categoryName).font(.subheadline.bold())
                }
                Section("Amount") {
                    TextField("Budget amount (₹)", text: $amountStr).keyboardType(.numberPad)
                    if let max = target.maxAllowed {
                        Text(exceedsMax ? "⚠ Exceeds parent — max \(max.shortINR) available" : "Max \(max.shortINR) available")
                            .font(.caption)
                            .foregroundStyle(exceedsMax ? .red : .secondary)
                    }
                }
                if target.isTrip && target.inheritsDates {
                    Section("Date Range") {
                        Text("\(startDate.shortDateString) – \(endDate.shortDateString)")
                            .font(.subheadline)
                        Text("Inherited from the trip")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if target.isTrip {
                    Section("Date Range") {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
                if target.existing != nil && target.canDelete {
                    Section {
                        Button("Delete Budget", role: .destructive) {
                            Task {
                                await vm.deleteBudget(id: target.existing!.id)
                                onDone(); dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(target.existing != nil ? "Edit Budget" : "Set Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount = amountValue else { return }
                        Task {
                            if target.isMonthMode, let existing = target.existing {
                                await vm.upsertCycleAmount(budgetId: existing.id, amount: amount)
                            } else {
                                // Tells the server which month is on screen, so creating a budget
                                // from a future month records that month instead of today's.
                                let recordsMonth = !target.isTrip && vm.viewMode == .month
                                let req = BudgetRequest(
                                    name: target.categoryName,
                                    defaultAmount: amount,
                                    categoryId: target.categoryId,
                                    isMonthly: !target.isTrip,
                                    cycleStartDay: target.isTrip ? 1 : vm.cycleDay,
                                    startDate: target.isTrip ? startDate : nil,
                                    endDate: target.isTrip ? endDate : nil,
                                    effectiveYear: recordsMonth ? vm.period.year : nil,
                                    effectiveMonth: recordsMonth ? vm.period.month : nil
                                )
                                if let existing = target.existing {
                                    await vm.updateBudget(id: existing.id, req: req)
                                } else {
                                    await vm.createBudget(req)
                                }
                            }
                            onDone(); dismiss()
                        }
                    }
                    .disabled(amountValue == nil || exceedsMax)
                }
            }
        }
    }
}

// MARK: - Settings Sheet

private struct BudgetSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: BudgetsViewModel
    @State private var cycleDay: Int

    init(vm: BudgetsViewModel) {
        self.vm = vm
        _cycleDay = State(initialValue: vm.cycleDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Start day: \(cycleDay)", value: $cycleDay, in: 1...28)
                } header: {
                    Text("Billing Cycle")
                } footer: {
                    // The day is not persisted on its own — it rides along on the next budget
                    // create or edit, same as Android.
                    Text("e.g. 15 → cycle runs 15th to 14th of next month. Applied the next time you set a budget.")
                }
            }
            .navigationTitle("Budget Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { vm.cycleDay = cycleDay; dismiss() }
                }
            }
        }
    }
}

// MARK: - Shared helpers

private struct BudgetCellButton: View {
    let vm: BudgetsViewModel
    let budget: Budget?
    var notSet: Bool = false
    var disabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        if notSet {
            Text("Not set").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
        } else {
            HStack(spacing: 4) {
                if let b = budget, let chip = vm.chip(b) { BudgetChipView(chip: chip) }
                Button(action: onTap) {
                    if let b = budget {
                        Text(vm.displayAmount(b).shortINR).font(.caption.bold())
                            .foregroundStyle(disabled ? Color.secondary : Color.accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                    } else {
                        Text("+ Set").font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
    }
}

private struct BudgetChipView: View {
    let chip: BudgetChip

    var body: some View {
        switch chip {
        case .frozen:
            Image(systemName: "lock.fill")
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Past months are read-only")
        case .custom:
            label("Custom", color: .accentColor)
        case .default:
            label("Default", color: .secondary)
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

// Free function rather than a method so every budget row shape can share it. SwiftUI's View
// initializers are @MainActor-isolated under Swift 6, and a top-level function is nonisolated by
// default, so the isolation has to be stated explicitly — every caller is a View body already.
@MainActor
private func progressSection(_ b: Budget) -> some View {
    VStack(spacing: 3) {
        ProgressBarView(spent: b.spent, total: b.effectiveAmount, showLabel: false)
        HStack {
            Text("\(b.spent.shortINR) spent").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("\(b.remaining.shortINR) left").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private extension Color {
    init(hex: String) { self = Color.fromHex(hex) }
}
