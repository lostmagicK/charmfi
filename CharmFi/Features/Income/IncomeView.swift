import SwiftUI

struct IncomeView: View {
    @Environment(AuthState.self) private var authState
    @State private var vm: IncomeViewModel?
    @State private var showManageSources = false
    @State private var addEntrySource: IncomeSource?
    @State private var editingEntry: IncomeEntry?

    var body: some View {
        VStack(spacing: 0) {
            if let vm {
                PeriodNavBar(period: Binding(get: { vm.period }, set: { vm.setPeriod($0) }), showModeToggle: false)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                if vm.isLoading && vm.month == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        if let err = vm.error {
                            ErrorBannerView(message: err) { vm.error = nil }.padding(.horizontal)
                        }
                        VStack(spacing: 12) {
                            totalsCard(vm: vm)
                            if vm.activeSources.isEmpty {
                                ContentUnavailableView("No Income Sources", systemImage: "banknote",
                                                        description: Text("Tap Manage to add one"))
                                    .padding(.top, 40)
                            } else {
                                ForEach(vm.activeSources) { source in
                                    sourceCard(vm: vm, source: source)
                                }
                            }
                            Spacer().frame(height: 20)
                        }
                        .padding(12)
                    }
                    .refreshable { await vm.load() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveReadableWidth()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Manage") { showManageSources = true }
            }
        }
        .task {
            let model = IncomeViewModel(auth: authState)
            vm = model
            await model.load()
        }
        .sheet(isPresented: $showManageSources) {
            if let vm { ManageSourcesSheet(vm: vm) }
        }
        .sheet(item: $addEntrySource) { source in
            if let vm { EntryFormSheet(vm: vm, source: source, entry: nil) }
        }
        .sheet(item: $editingEntry) { entry in
            if let vm, let source = vm.sources.first(where: { $0.id == entry.incomeSourceId }) {
                EntryFormSheet(vm: vm, source: source, entry: entry)
            }
        }
    }

    private func totalsCard(vm: IncomeViewModel) -> some View {
        let m = vm.month
        return HStack(spacing: 0) {
            totalPill(label: "FIXED", value: m?.fixedTotal ?? 0)
            Divider().frame(height: 36)
            totalPill(label: "VARIABLE", value: m?.variableTotal ?? 0)
            Divider().frame(height: 36)
            totalPill(label: "TOTAL", value: m?.total ?? 0, emphasize: true)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func totalPill(label: String, value: Double, emphasize: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value.formattedINR)
                .font(emphasize ? .subheadline.bold() : .subheadline)
                .foregroundStyle(emphasize ? Color.accentColor : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceCard(vm: IncomeViewModel, source: IncomeSource) -> some View {
        let entries = vm.entries(for: source.id)
        let amount = vm.amount(for: source.id)
        let total = vm.month?.total ?? 0
        let sharePct = total > 0 ? Int((amount / total) * 100) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(Color.fromHex(source.color ?? "#64748b")).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.name).font(.subheadline.bold())
                    Text(source.kind == .fixed ? "Fixed · monthly" : "Variable")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(amount.formattedINR).font(.subheadline.bold())
                    if total > 0 { Text("\(sharePct)% of total").font(.caption2).foregroundStyle(.secondary) }
                }
            }

            ForEach(entries) { entry in
                entryRow(entry: entry)
                    .onTapGesture { editingEntry = entry }
            }

            if source.kind == .variable {
                Button { addEntrySource = source } label: {
                    Label("Add receipt", systemImage: "plus.circle")
                }.font(.caption)
            } else if entries.isEmpty {
                Button { addEntrySource = source } label: {
                    Label("Set amount for this month", systemImage: "plus.circle")
                }.font(.caption)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func entryRow(entry: IncomeEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.receivedOn.shortDateString).font(.caption)
                    if entry.isAutoFilled {
                        Text("expected").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(.systemGray5)).clipShape(Capsule())
                    }
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.amount.formattedINR).font(.caption.bold())
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Manage Sources

private struct ManageSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: IncomeViewModel
    @State private var editingSource: IncomeSource?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.sources) { source in
                    HStack {
                        Circle().fill(Color.fromHex(source.color ?? "#64748b")).frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text(source.name)
                            Text(source.kind.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !source.isActive {
                            Text("Inactive").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingSource = source }
                }
            }
            .navigationTitle("Income Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { showAdd = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showAdd) { SourceFormSheet(vm: vm, source: nil) }
            .sheet(item: $editingSource) { SourceFormSheet(vm: vm, source: $0) }
        }
    }
}

private struct SourceFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: IncomeViewModel
    let source: IncomeSource?

    @State private var name = ""
    @State private var kind: IncomeKind = .fixed
    @State private var defaultAmount = ""
    @State private var dayOfMonth = ""
    @State private var color = "#3b82f6"
    @State private var isActive = true
    @State private var showDeleteConfirm = false

    init(vm: IncomeViewModel, source: IncomeSource?) {
        self.vm = vm; self.source = source
        if let s = source {
            _name = State(initialValue: s.name)
            _kind = State(initialValue: s.kind)
            _defaultAmount = State(initialValue: s.defaultAmount > 0 ? String(s.defaultAmount) : "")
            _dayOfMonth = State(initialValue: s.dayOfMonth.map { String($0) } ?? "1")
            _color = State(initialValue: s.color ?? "#3b82f6")
            _isActive = State(initialValue: s.isActive)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(IncomeKind.allCases) { k in Text(k.displayName).tag(k) }
                    }
                    if kind == .fixed {
                        TextField("Monthly amount", text: $defaultAmount).keyboardType(.decimalPad)
                        TextField("Expected day (1-28)", text: $dayOfMonth).keyboardType(.numberPad)
                    }
                    Toggle("Active", isOn: $isActive)
                }
                Section("Color") {
                    ColorSwatchPicker(hex: $color)
                }
                if let source {
                    Section {
                        Button("Delete Source", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(source == nil ? "Add Source" : "Edit Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let req = IncomeSourceRequest(
                            name: name, kind: kind,
                            defaultAmount: Double(defaultAmount) ?? 0,
                            dayOfMonth: kind == .fixed ? (Int(dayOfMonth) ?? 1) : nil,
                            startDate: source?.startDate ?? Date(),
                            endDate: source?.endDate,
                            icon: nil, color: color,
                            sortOrder: source?.sortOrder ?? 0,
                            isActive: isActive
                        )
                        Task {
                            if let source { await vm.updateSource(id: source.id, req: req) }
                            else { await vm.createSource(req) }
                            dismiss()
                        }
                    }.disabled(name.isEmpty)
                }
            }
            .confirmationDialog("Delete this income source? Its recorded entries stay, but it stops being offered for new ones.",
                                 isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let source { Task { await vm.deleteSource(id: source.id); dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

// MARK: - Entry add/edit

private struct EntryFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: IncomeViewModel
    let source: IncomeSource
    let entry: IncomeEntry?

    @State private var amount = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var showDeleteConfirm = false

    init(vm: IncomeViewModel, source: IncomeSource, entry: IncomeEntry?) {
        self.vm = vm; self.source = source; self.entry = entry
        if let e = entry {
            _amount = State(initialValue: String(e.amount))
            _date = State(initialValue: e.receivedOn)
            _note = State(initialValue: e.note ?? "")
        } else {
            _amount = State(initialValue: source.defaultAmount > 0 ? String(source.defaultAmount) : "")
            _date = State(initialValue: vm.defaultEntryDate(for: source))
        }
    }

    // Materialized fixed-source rows (periodStart != nil) aren't real receipts — only actual
    // entries the user recorded can be deleted. Mirrors Android's delete-eligibility check.
    private var canDelete: Bool { entry != nil && entry?.periodStart == nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount", text: $amount).keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Note (optional)", text: $note)
                if canDelete {
                    Section {
                        Button("Delete Entry", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Add Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amt = Double(amount) else { return }
                        Task {
                            if let entry {
                                await vm.updateEntry(id: entry.id, req: IncomeEntryUpdateRequest(
                                    amount: amt, receivedOn: date, note: note.isEmpty ? nil : note))
                            } else {
                                await vm.createEntry(IncomeEntryRequest(
                                    incomeSourceId: source.id, amount: amt, receivedOn: date,
                                    note: note.isEmpty ? nil : note))
                            }
                            dismiss()
                        }
                    }.disabled(Double(amount) == nil)
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entry { Task { await vm.deleteEntry(id: entry.id); dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
