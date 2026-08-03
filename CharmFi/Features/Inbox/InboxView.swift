import SwiftUI
import Combine

struct InboxView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @State private var vm: InboxViewModel?
    @State private var showScanOptions = false
    @State private var showScanEmailSheet = false
    @State private var showScanPdfSheet = false
    @State private var showFilterSheet = false
    @State private var filterTarget = ""   // "method" | "date"
    @State private var editingDraft: Expense? = nil
    @State private var viewMerchant: String? = nil
    @State private var showBulkCategoryPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm { inboxContent(vm: vm) }
                else { ProgressView() }
            }
            .navigationTitle("Expense Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: searchTextBinding, prompt: "Search merchant")
            .toolbar { toolbarItems }
            .overlay(alignment: .bottomTrailing) { fabButton }
        }
        .task {
            let (model, isNew) = ViewModelStore.shared.model(InboxViewModel.self, auth: authState) {
                $0.setModelContext(modelContext)
            }
            vm = model
            if isNew { await model.load() }
        }
        .confirmationDialog("Scan", isPresented: $showScanOptions, titleVisibility: .visible) {
            Button("Scan from Email") { showScanEmailSheet = true }
            Button("Upload PDF") { showScanPdfSheet = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showScanEmailSheet) {
            if let vm { ScanEmailSheet(vm: vm) }
        }
        .sheet(isPresented: $showScanPdfSheet) {
            if let vm { ScanPdfSheet(vm: vm) }
        }
        .sheet(item: $editingDraft) { draft in
            if let vm {
                EditExpenseSheet(expense: draft, categories: vm.categories) { merchant, comment, catId, method in
                    Task { await vm.updateDraft(id: draft.id,
                        req: UpdateExpenseRequest(merchant: merchant, paymentMethod: method,
                                                  comment: comment, categoryId: catId)) }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewMerchant != nil },
            set: { if !$0 { viewMerchant = nil } }
        )) {
            if let vm, let merchant = viewMerchant {
                MerchantTransactionsView(vm: vm, merchant: merchant, onDismiss: { viewMerchant = nil })
            }
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(get: { vm?.searchText ?? "" }, set: { vm?.searchText = $0 })
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if let vm {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if vm.selectionMode { vm.exitSelectionMode() }
                    else { vm.showFilters.toggle() }
                } label: {
                    Image(systemName: vm.selectionMode ? "xmark" : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { vm.groupByMerchant.toggle() } label: {
                    Image(systemName: vm.groupByMerchant ? "rectangle.grid.1x2" : "list.bullet")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Group {
            if let vm, !vm.selectionMode {
                let isScanning: Bool = {
                    if case .scanning = vm.state { return true }
                    if case .syncing = vm.state { return true }
                    return false
                }()
                Button { if !isScanning { showScanOptions = true } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.viewfinder")
                        Text(isScanning ? "Scanning…" : "Scan")
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(isScanning ? Color(.systemGray3) : Color.accentColor, in: Capsule())
                    .shadow(radius: 4)
                }
                .padding(20)
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func inboxContent(vm: InboxViewModel) -> some View {
        ZStack {
            VStack(spacing: 0) {
                // Scan progress overlay
                if case .scanning(let cur, let tot, let found, let start) = vm.state {
                    scanProgressBanner(current: cur, total: tot, found: found, startedAt: start)
                }

                // Done banner
                if case .done(let found, let skipped) = vm.state {
                    doneBanner(found: found, skipped: skipped)
                }

                // Error banner
                if case .error(let msg) = vm.state {
                    ErrorBannerView(message: msg) { vm.state = .idle }
                }

                if vm.duplicateCount > 0 && !vm.selectionMode {
                    duplicateBanner(vm: vm)
                }

                if vm.selectionMode {
                    selectionBar(vm: vm)
                }

                if case .scanning = vm.state {
                    scanningBody(vm: vm)
                } else {
                    draftList(vm: vm)
                }
            }

            if let toast = vm.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.black.opacity(0.85), in: Capsule())
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { vm.toast = nil }
                }
            }
        }
        .animation(.easeInOut, value: vm.toast)
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(vm: vm, target: filterTarget)
        }
    }

    // MARK: - Scanning body

    @ViewBuilder
    private func scanningBody(vm: InboxViewModel) -> some View {
        if case .scanning(let cur, let tot, let found, let start) = vm.state {
            VStack(spacing: 16) {
                Spacer()
                Text("Scanning emails…").font(.title3.bold())
                ProgressView(value: tot > 0 ? Double(cur) / Double(tot) : 0)
                    .padding(.horizontal)
                Text("\(cur) / \(tot)  •  \(found) found")
                    .font(.subheadline).foregroundStyle(.secondary)
                let elapsed = Int(Date().timeIntervalSince(start))
                Text(formatElapsed(elapsed)).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Draft list

    @ViewBuilder
    private func draftList(vm: InboxViewModel) -> some View {
        let filtered = vm.filteredDrafts

        if filtered.isEmpty && vm.drafts.isEmpty {
            emptyState(vm: vm)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    // Filter chips
                    if !vm.drafts.isEmpty { filterChips(vm: vm) }

                    if vm.groupByMerchant {
                        if vm.merchantGroups.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.up.slash").font(.system(size: 40)).foregroundStyle(.secondary)
                                Text("No merchants with 2+ transactions").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 60)
                        } else {
                            AdaptiveGrid(minColumnWidth: 360, spacing: 12) {
                                ForEach(vm.merchantGroups) { group in
                                    MerchantGroupCard(
                                        group: group,
                                        categories: vm.categories,
                                        onApplyCategory: { catId in await vm.applyCategoryToMerchant(group.merchant, categoryId: catId) },
                                        onSubmitAll: { await vm.submitMerchantGroup(group.merchant) },
                                        onViewTransactions: { viewMerchant = group.merchant }
                                    )
                                }
                            }
                        }
                    } else if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 40)).foregroundStyle(.secondary)
                            Text("No drafts match the current filter").foregroundStyle(.secondary)
                            Button("Clear Filters") { vm.clearFilters() }
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        AdaptiveGrid(minColumnWidth: 360, spacing: 12) {
                            ForEach(filtered) { draft in
                                DraftExpenseCard(
                                    draft: draft,
                                    categories: vm.categories,
                                    accounts: vm.accounts,
                                    familyMembers: vm.familyMembers,
                                    selectionMode: vm.selectionMode,
                                    isSelected: vm.selectedIds.contains(draft.id),
                                    isJustSubmitted: vm.justSubmittedIds.contains(draft.id),
                                    dupKind: vm.dupKind(draft),
                                    onUpdate: { req in await vm.updateDraft(id: draft.id, req: req) },
                                    onApprove: { await vm.approveDraft(id: draft.id) },
                                    onDiscard: { await vm.discardDraft(id: draft.id) },
                                    onSplit: { splits in await vm.splitDraft(draft: draft, splits: splits) },
                                    onSettle: { recipientUserId, method, accountId, comment in
                                        await vm.settleFromDraft(draftId: draft.id, recipientUserId: recipientUserId,
                                                                 amount: draft.amount, method: method,
                                                                 accountId: accountId, comment: comment,
                                                                 date: draft.transactionDate)
                                    },
                                    onToggleSelect: { vm.toggleSelection(draft.id) },
                                    onLongPress: { vm.enterSelectionMode(); vm.toggleSelection(draft.id) }
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Filter chips

    private func filterChips(vm: InboxViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("\(vm.filteredDrafts.count)/\(vm.drafts.count)")
                    .font(.caption2).foregroundStyle(.secondary)

                activeChip(vm.filterMethod?.displayName, icon: "creditcard") {
                    filterTarget = "method"; showFilterSheet = true
                } onClear: { vm.filterMethod = nil }

                activeChip(vm.filterDate.map { String($0.prefix(10)) }, icon: "calendar") {
                    filterTarget = "date"; showFilterSheet = true
                } onClear: { vm.filterDate = nil }

                categorizedChip(vm: vm, value: true, label: "Categorized", icon: "checkmark.circle")
                categorizedChip(vm: vm, value: false, label: "Uncategorized", icon: "circle")
            }
            .padding(.horizontal, 4).padding(.vertical, 4)
        }
    }

    private func categorizedChip(vm: InboxViewModel, value: Bool, label: String, icon: String) -> some View {
        let isActive = vm.filterCategorized == value
        return Button {
            vm.filterCategorized = isActive ? nil : value
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func activeChip(_ value: String?, icon: String, onTap: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(value ?? (icon == "creditcard" ? "Method" : "Date")).font(.caption)
                if value != nil {
                    Image(systemName: "xmark").font(.caption2)
                        .onTapGesture { onClear() }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(value != nil ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
            .foregroundStyle(value != nil ? Color.accentColor : .secondary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Selection bar

    private func selectionBar(vm: InboxViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(vm.selectedIds.count) of \(vm.filteredDrafts.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { vm.selectAll() } label: {
                    Label("All", systemImage: "checkmark.square")
                        .font(.caption)
                }
                .disabled(vm.isBulkProcessing || vm.selectedIds.count == vm.filteredDrafts.count)
                Button { vm.selectNone() } label: {
                    Label("None", systemImage: "square")
                        .font(.caption)
                }
                .disabled(vm.isBulkProcessing || vm.selectedIds.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            Divider()

            if vm.isBulkProcessing {
                VStack(spacing: 4) {
                    if let progress = vm.bulkProgress {
                        ProgressView(value: progress.total > 0 ? Double(progress.current) / Double(progress.total) : 0)
                        Text("Discarding \(progress.current) / \(progress.total)…")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Submitting…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    Task { await vm.discardSelected() }
                } label: {
                    Label("Discard", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(vm.isBulkProcessing || vm.selectedIds.isEmpty)

                Button {
                    showBulkCategoryPicker = true
                } label: {
                    Label("Category", systemImage: "tag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(vm.isBulkProcessing || vm.selectedIds.isEmpty)

                Button {
                    Task { await vm.submitSelected() }
                } label: {
                    Label("Submit", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isBulkProcessing || vm.selectedIds.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showBulkCategoryPicker) {
            CategoryPickerSheet(categories: vm.categories, selectedId: nil) { catId in
                Task { await vm.applyCategoryToSelected(catId) }
            }
        }
    }

    // MARK: - Banners

    private func scanProgressBanner(current: Int, total: Int, found: Int, startedAt: Date) -> some View {
        HStack {
            ProgressView().scaleEffect(0.8)
            Text("\(current)/\(total) • \(found) found")
                .font(.caption)
            Spacer()
            Text(formatElapsed(Int(Date().timeIntervalSince(startedAt))))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
    }

    private func duplicateBanner(vm: InboxViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc.fill").foregroundStyle(.orange)
            Text("\(vm.duplicateCount) possible duplicate\(vm.duplicateCount == 1 ? "" : "s")")
                .font(.caption)
            Spacer()
            if vm.isBulkProcessing {
                ProgressView().scaleEffect(0.7)
            } else {
                Button { Task { await vm.removeDuplicates() } } label: {
                    Text("Remove").font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private func doneBanner(found: Int, skipped: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("\(found) found  •  \(skipped) skipped").font(.caption)
            Spacer()
            Button { if let vm { vm.state = .idle } } label: {
                Image(systemName: "xmark").font(.caption)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
    }

    private func emptyState(vm: InboxViewModel) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 56)).foregroundStyle(.secondary)
            if case .done(let found, let skipped) = vm.state {
                Text("All caught up!").font(.title3.bold()).foregroundStyle(.secondary)
                Text("\(found) found  •  \(skipped) skipped").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Tap 'Scan' to import expenses.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Scan Email Sheet

private struct ScanEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: InboxViewModel
    @State private var showDatePicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("Gmail") {
                    if vm.isGmailConnected {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.gmailEmail ?? "Connected").font(.subheadline)
                                if let last = vm.lastSyncDate {
                                    Text("Last sync: \(last.shortDateString)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Disconnect") { vm.signOutGmail() }
                                .font(.caption).foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            Task { await vm.signInGmail(); vm.refreshGmailState() }
                        } label: {
                            Label("Connect Gmail Account", systemImage: "envelope.badge")
                        }
                    }
                }

                if vm.isGmailConnected {
                    Section("Scan") {
                        // Date picker — tap date row to expand, picks dismiss it
                        Button {
                            withAnimation { showDatePicker.toggle() }
                        } label: {
                            HStack {
                                Text("Scan since").foregroundStyle(.primary)
                                Spacer()
                                Text(vm.scanSinceDate.shortDateString)
                                    .foregroundStyle(Color.accentColor)
                                Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }

                        if showDatePicker {
                            DatePicker("", selection: Bindable(vm).scanSinceDate, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .onChange(of: vm.scanSinceDate) { _, _ in
                                    withAnimation { showDatePicker = false }
                                }
                        }

                        Button {
                            dismiss()
                            Task { await vm.scanEmail(since: vm.lastSyncDate ?? vm.scanSinceDate) }
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("From last scan").font(.subheadline.bold())
                                    Text("Since \(vm.lastSyncDate?.shortDateString ?? vm.scanSinceDate.shortDateString)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)

                        Button {
                            dismiss()
                            Task { await vm.scanEmail(since: vm.scanSinceDate) }
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("From chosen date").font(.subheadline.bold())
                                    Text(vm.scanSinceDate.shortDateString)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }

                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.shield").foregroundStyle(Color.accentColor)
                            Text("Google credentials stay on this device and are never sent to CharmFi servers.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Scan from Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Scan PDF Sheet

private struct ScanPdfSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: InboxViewModel

    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var password = ""
    @State private var isParsing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                fileSection
                passwordSection
                if let msg = errorMessage { errorSection(msg) }
                importSection
            }
            .navigationTitle("Upload PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isParsing)
                }
            }
            .interactiveDismissDisabled(isParsing)
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result {
                    releaseFile()
                    _ = url.startAccessingSecurityScopedResource()
                    selectedFileURL = url
                    errorMessage = nil
                }
            }
            .onDisappear { releaseFile() }
        }
    }

    @ViewBuilder private var fileSection: some View {
        Section {
            Button { showFilePicker = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedFileURL == nil ? "doc.badge.plus" : "doc.fill")
                        .foregroundStyle(Color.accentColor)
                    if let url = selectedFileURL {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline).foregroundStyle(.primary)
                                .lineLimit(1).truncationMode(.middle)
                            Text("Tap to choose a different file")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("Choose PDF File").foregroundStyle(.primary)
                        Spacer()
                    }
                }
            }
        } header: {
            Text("Bank Statement")
        } footer: {
            Text("Upload an HDFC account statement (PDF). Debit transactions become draft expenses.")
        }
    }

    @ViewBuilder private var passwordSection: some View {
        Section {
            HStack {
                Image(systemName: "lock").foregroundStyle(.secondary)
                SecureField("Password (if protected)", text: $password)
            }
        } footer: {
            Text("Bank statements are often protected. Leave blank if yours isn't.")
        }
    }

    @ViewBuilder private func errorSection(_ msg: String) -> some View {
        Section {
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        }
    }

    @ViewBuilder private var importSection: some View {
        Section {
            Button { runImport() } label: {
                HStack {
                    Spacer()
                    if isParsing { ProgressView().scaleEffect(0.8).padding(.trailing, 6) }
                    Text(isParsing ? "Importing…" : "Import Transactions")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFileURL == nil || isParsing)
        } footer: {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Color.accentColor)
                Text("The PDF is uploaded securely to extract transactions, then discarded.")
                    .font(.caption)
            }
        }
    }

    private func runImport() {
        guard let url = selectedFileURL else { return }
        isParsing = true
        errorMessage = nil
        Task {
            let result = await vm.importPdf(
                fileURL: url,
                password: password.isEmpty ? nil : password
            )
            isParsing = false
            if result.success {
                dismiss()   // Inbox shows the imported drafts + a "done" banner.
            } else {
                errorMessage = result.message
            }
        }
    }

    private func releaseFile() {
        selectedFileURL?.stopAccessingSecurityScopedResource()
    }
}

// MARK: - Filter Sheet

private struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: InboxViewModel
    let target: String

    var body: some View {
        NavigationStack {
            List {
                if target == "method" {
                    Button("All Methods") { vm.filterMethod = nil; dismiss() }
                        .foregroundStyle(vm.filterMethod == nil ? Color.accentColor : .primary)
                    ForEach(PaymentMethod.allCases) { m in
                        Button(m.displayName) { vm.filterMethod = m; dismiss() }
                            .foregroundStyle(vm.filterMethod == m ? Color.accentColor : .primary)
                    }
                } else {
                    Button("All Dates") { vm.filterDate = nil; dismiss() }
                        .foregroundStyle(vm.filterDate == nil ? Color.accentColor : .primary)
                    ForEach(vm.availableDates, id: \.self) { d in
                        Button(d) { vm.filterDate = d; dismiss() }
                            .foregroundStyle(vm.filterDate == d ? Color.accentColor : .primary)
                    }
                }
            }
            .navigationTitle(target == "method" ? "Filter by Method" : "Filter by Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Draft Expense Card

struct SplitItem: Identifiable {
    var id = UUID()
    var amount: String
    var merchant: String = ""
    var categoryId: String? = nil
}

struct DraftExpenseCard: View {
    let draft: Expense
    let categories: [Category]
    let accounts: [PaymentAccount]
    let familyMembers: [FamilyMember]
    let selectionMode: Bool
    let isSelected: Bool
    var isJustSubmitted: Bool = false
    var dupKind: DuplicateKind? = nil
    var onUpdate: (UpdateExpenseRequest) async -> Void
    var onApprove: () async -> Void
    var onDiscard: () async -> Void
    var onSplit: ([SplitItem]) async -> Void
    var onSettle: (String, PaymentMethod, String?, String?) async -> Void = { _, _, _, _ in }
    var onToggleSelect: () -> Void
    var onLongPress: () -> Void

    @State private var merchant: String
    @State private var categoryId: String?
    @State private var method: PaymentMethod
    @State private var accountId: String?
    @State private var comment: String
    @State private var paidForUserId: String?
    @State private var isRepayment = false
    @State private var showEmail = false
    @State private var showCategoryPicker = false
    @State private var showSplitSheet = false
    @State private var debounceTask: Task<Void, Never>?

    init(draft: Expense, categories: [Category], accounts: [PaymentAccount],
         familyMembers: [FamilyMember] = [],
         selectionMode: Bool, isSelected: Bool, isJustSubmitted: Bool = false,
         dupKind: DuplicateKind? = nil,
         onUpdate: @escaping (UpdateExpenseRequest) async -> Void,
         onApprove: @escaping () async -> Void,
         onDiscard: @escaping () async -> Void,
         onSplit: @escaping ([SplitItem]) async -> Void = { _ in },
         onSettle: @escaping (String, PaymentMethod, String?, String?) async -> Void = { _, _, _, _ in },
         onToggleSelect: @escaping () -> Void,
         onLongPress: @escaping () -> Void) {
        self.draft = draft; self.categories = categories; self.accounts = accounts
        self.familyMembers = familyMembers
        self.selectionMode = selectionMode; self.isSelected = isSelected
        self.isJustSubmitted = isJustSubmitted
        self.dupKind = dupKind
        self.onUpdate = onUpdate; self.onApprove = onApprove; self.onDiscard = onDiscard
        self.onSplit = onSplit; self.onSettle = onSettle
        self.onToggleSelect = onToggleSelect; self.onLongPress = onLongPress
        _merchant = State(initialValue: draft.merchant)
        _categoryId = State(initialValue: draft.categoryId)
        _method = State(initialValue: draft.paymentMethod)
        _accountId = State(initialValue: draft.paymentAccountId)
        _comment = State(initialValue: draft.comment ?? "")
        _paidForUserId = State(initialValue: draft.sharedByUserId)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3).onTapGesture { onToggleSelect() }
            }

            VStack(alignment: .leading, spacing: 10) {
                // Amount + date header
                HStack {
                    Text(draft.amount.formattedINR)
                        .font(.title3.bold()).foregroundStyle(Color.accentColor)
                    if let dupKind { dupBadge(dupKind) }
                    Spacer()
                    Text(String(draft.transactionDate.description.prefix(10)))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // Full email toggle
                if let raw = draft.rawSmsText, !raw.isEmpty {
                    HStack {
                        Button {
                            withAnimation { showEmail.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showEmail ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                Text(showEmail ? "Hide email" : "View email")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = raw
                        } label: {
                            Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if showEmail {
                        Text(String(raw.prefix(300)))
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                Divider()

                // Self / For Someone (only when family members exist)
                if !familyMembers.isEmpty {
                    Picker("", selection: Binding(
                        get: { paidForUserId != nil },
                        set: { isFor in
                            paidForUserId = isFor ? familyMembers.first?.userId : nil
                            isRepayment = false
                            scheduleUpdate()
                        }
                    )) {
                        Text("Self").tag(false)
                        Text("For Someone").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if paidForUserId != nil {
                        Menu {
                            ForEach(familyMembers) { m in
                                Button(m.displayName) { paidForUserId = m.userId; scheduleUpdate() }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "person").font(.caption)
                                Text(familyMembers.first(where: { $0.userId == paidForUserId })?.displayName ?? "Select member")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                        }
                        .foregroundStyle(.primary)

                        Picker("", selection: $isRepayment) {
                            Text("Regular").tag(false)
                            Text("Repayment").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // Merchant (hidden in repayment)
                if !(paidForUserId != nil && isRepayment) {
                    TextField("Merchant", text: $merchant)
                        .font(.subheadline.bold())
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                        .onChange(of: merchant) { scheduleUpdate() }
                }

                // Payment method
                outlinedMenu("Payment Mode", value: method.displayName) {
                    ForEach(PaymentMethod.allCases) { m in
                        Button(m.displayName) { method = m; scheduleUpdate() }
                    }
                }

                // Account picker
                outlinedMenu("Account",
                    value: accounts.first(where: { $0.id == accountId }).map {
                        $0.last4 != nil ? "\($0.name) ••\($0.last4!)" : $0.name
                    } ?? "None / Cash"
                ) {
                    Button("None / Cash") { accountId = nil; scheduleUpdate() }
                    ForEach(accounts.filter(\.isActive)) { a in
                        Button { accountId = a.id; scheduleUpdate() } label: {
                            Text(a.last4 != nil ? "\(a.name) ••\(a.last4!)" : a.name)
                        }
                    }
                }

                // Category (hidden when paying for someone)
                if paidForUserId == nil {
                    Button { showCategoryPicker = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Category").font(.caption).foregroundStyle(.secondary)
                                Text(categoryId != nil ? categoryLabel(categories, categoryId) : "None")
                                    .font(.subheadline).foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                    }
                }

                // Comment
                TextField("Comment", text: $comment)
                    .font(.subheadline)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                    .onChange(of: comment) { scheduleUpdate() }

                // Actions: Discard | Split | Submit/Settle
                if isJustSubmitted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Submitted").font(.subheadline.bold()).foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)
                } else if !selectionMode {
                    HStack(spacing: 8) {
                        Button(role: .destructive) {
                            Task { await onDiscard() }
                        } label: {
                            Label("Discard", systemImage: "trash")
                                .font(.caption.bold()).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Button { showSplitSheet = true } label: {
                            Label("Split", systemImage: "arrow.triangle.branch")
                                .font(.caption.bold()).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            if isRepayment, let recipientUserId = paidForUserId {
                                Task { await onSettle(recipientUserId, method, accountId, comment.isEmpty ? nil : comment) }
                            } else {
                                Task { await onApprove() }
                            }
                        } label: {
                            Label(isRepayment && paidForUserId != nil ? "Settle" : "Submit",
                                  systemImage: "checkmark.circle.fill")
                                .font(.caption.bold()).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            isJustSubmitted ? RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.12)) : nil
        )
        .overlay(
            isSelected ? RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2) : nil
        )
        .overlay(
            dupKind != nil && !isSelected
                ? RoundedRectangle(cornerRadius: 12).strokeBorder(
                    dupKind == .submitted ? Color.red.opacity(0.6) : Color.orange.opacity(0.6), lineWidth: 1.5)
                : nil
        )
        .onLongPressGesture { onLongPress() }
        .onTapGesture { if selectionMode { onToggleSelect() } }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(categories: categories, selectedId: categoryId) { id in
                categoryId = id; scheduleUpdate()
            }
        }
        .sheet(isPresented: $showSplitSheet) {
            SplitExpenseSheet(totalAmount: draft.amount, originalMerchant: draft.merchant,
                              categories: categories) { splits in
                Task { await onSplit(splits) }
            }
        }
    }

    @ViewBuilder
    private func dupBadge(_ kind: DuplicateKind) -> some View {
        let color: Color = kind == .submitted ? .red : .orange
        let text = kind == .submitted ? "Already recorded" : "Possible duplicate"
        let icon = kind == .submitted ? "exclamationmark.circle.fill" : "doc.on.doc.fill"
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func outlinedMenu<Content: View>(_ label: String, value: String,
                                             @ViewBuilder items: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary).padding(.leading, 2)
            Menu { items() } label: {
                HStack {
                    Text(value).font(.subheadline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
            }
        }
    }

    private func scheduleUpdate() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let req = UpdateExpenseRequest(
                merchant: merchant.isEmpty ? nil : merchant,
                paymentMethod: method,
                comment: comment.isEmpty ? nil : comment,
                categoryId: categoryId,
                paymentAccountId: accountId
            )
            await onUpdate(req)
        }
    }
}

// MARK: - Split Expense Sheet

struct SplitExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let totalAmount: Double
    let originalMerchant: String
    let categories: [Category]
    let onConfirm: ([SplitItem]) -> Void

    @State private var splits: [SplitItem]
    @State private var categoryPickerIndex: Int?

    init(totalAmount: Double, originalMerchant: String, categories: [Category],
         onConfirm: @escaping ([SplitItem]) -> Void) {
        self.totalAmount = totalAmount; self.originalMerchant = originalMerchant
        self.categories = categories; self.onConfirm = onConfirm
        let half = String(format: "%.2f", totalAmount / 2)
        _splits = State(initialValue: [SplitItem(amount: half), SplitItem(amount: half)])
    }

    private var allocated: Double { splits.compactMap { Double($0.amount) }.reduce(0, +) }
    private var remaining: Double { totalAmount - allocated }
    private var isValid: Bool { abs(remaining) < 0.01 && splits.allSatisfy { (Double($0.amount) ?? 0) > 0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text("Total: \(totalAmount.formattedINR)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }

                    // Splits
                    ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                        splitRow(idx: idx, split: split)
                    }

                    // Remaining indicator
                    HStack(spacing: 6) {
                        Image(systemName: isValid ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(isValid ? .green : remaining < -0.01 ? .red : .orange)
                        if isValid {
                            Text("Splits add up correctly").font(.caption)
                        } else if remaining > 0.01 {
                            Text("\(remaining.formattedINR) unallocated").font(.caption)
                            Spacer()
                            Button("Auto-fill") {
                                if let last = splits.last {
                                    let newAmt = (Double(last.amount) ?? 0) + remaining
                                    splits[splits.count - 1].amount = String(format: "%.2f", newAmt)
                                }
                            }
                            .font(.caption)
                        } else {
                            Text("\((-remaining).formattedINR) over-allocated").font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(10)
                    .background(isValid ? Color.green.opacity(0.1) : Color.orange.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 8))

                    // Add split
                    Button {
                        let newAmt = remaining > 0.01 ? String(format: "%.2f", remaining) : "0.00"
                        splits.append(SplitItem(amount: newAmt))
                    } label: {
                        Label("Add split", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
            }
            .navigationTitle("Split Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm Split") {
                        onConfirm(splits)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: Binding(
                get: { categoryPickerIndex != nil },
                set: { if !$0 { categoryPickerIndex = nil } }
            )) {
                if let idx = categoryPickerIndex, splits.indices.contains(idx) {
                    CategoryPickerSheet(categories: categories, selectedId: splits[idx].categoryId) {
                        splits[idx].categoryId = $0
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func splitRow(idx: Int, split: SplitItem) -> some View {
        let pct = totalAmount > 0 ? (Double(split.amount) ?? 0) / totalAmount * 100 : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Split \(idx + 1)").font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if (Double(split.amount) ?? 0) > 0 {
                    Text(String(format: "%.1f%%", pct)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if splits.count > 2 {
                    Button { splits.remove(at: idx) } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Amount", text: Binding(
                    get: { splits[idx].amount },
                    set: { splits[idx].amount = $0 }
                ))
                .keyboardType(.decimalPad)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))

                TextField("Merchant (opt.)", text: Binding(
                    get: { splits[idx].merchant },
                    set: { splits[idx].merchant = $0 }
                ))
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
            }

            // Category for this split
            Button {
                categoryPickerIndex = idx
            } label: {
                HStack {
                    Image(systemName: "tag").font(.caption2)
                    Text(splits[idx].categoryId != nil
                         ? categoryLabel(categories, splits[idx].categoryId) : "Category (opt.)")
                        .font(.caption).foregroundStyle(splits[idx].categoryId != nil ? Color.accentColor : .secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
    }
}

// MARK: - Merchant Group Card

struct MerchantGroupCard: View {
    let group: InboxViewModel.MerchantGroup
    let categories: [Category]
    var onApplyCategory: (String?) async -> Void
    var onSubmitAll: () async -> Void
    var onViewTransactions: () -> Void

    @State private var showCategoryPicker = false
    @State private var isSubmitting = false

    private var stackLayers: Int { min(group.count - 1, 2) }

    var body: some View {
        ZStack {
            ForEach(0..<stackLayers, id: \.self) { i in
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .offset(x: 0, y: CGFloat(i + 1) * 5)
                    .opacity(1 - Double(i + 1) * 0.25)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(group.merchant).font(.subheadline.bold())
                    Spacer()
                    Text("\(group.count) txns")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }

                Text(group.total.formattedINR)
                    .font(.title3.bold()).foregroundStyle(Color.accentColor)

                Button { showCategoryPicker = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Category").font(.caption).foregroundStyle(.secondary)
                            Text(group.sharedCategoryId != nil
                                 ? categoryLabel(categories, group.sharedCategoryId) : "Mixed")
                                .font(.subheadline).foregroundStyle(.primary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3), lineWidth: 1))
                }

                HStack(spacing: 8) {
                    Button(action: onViewTransactions) {
                        Label("View transactions", systemImage: "list.bullet")
                            .font(.caption.bold()).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { isSubmitting = true; await onSubmitAll(); isSubmitting = false }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Submit all", systemImage: "checkmark.circle.fill")
                                .font(.caption.bold()).frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(categories: categories, selectedId: group.sharedCategoryId) { id in
                Task { await onApplyCategory(id) }
            }
        }
    }
}

// MARK: - Merchant Transactions Drill-in

struct MerchantTransactionsView: View {
    let vm: InboxViewModel
    let merchant: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            let rows = vm.draftsForMerchant(merchant)
            ScrollView {
                if rows.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("All transactions handled").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    AdaptiveGrid(minColumnWidth: 360, spacing: 12) {
                        ForEach(rows) { draft in
                            DraftExpenseCard(
                                draft: draft,
                                categories: vm.categories,
                                accounts: vm.accounts,
                                familyMembers: vm.familyMembers,
                                selectionMode: false,
                                isSelected: false,
                                isJustSubmitted: vm.justSubmittedIds.contains(draft.id),
                                dupKind: vm.dupKind(draft),
                                onUpdate: { req in await vm.updateDraft(id: draft.id, req: req) },
                                onApprove: { await vm.approveDraft(id: draft.id) },
                                onDiscard: { await vm.discardDraft(id: draft.id) },
                                onSplit: { splits in await vm.splitDraft(draft: draft, splits: splits) },
                                onSettle: { recipientUserId, method, accountId, comment in
                                    await vm.settleFromDraft(draftId: draft.id, recipientUserId: recipientUserId,
                                                             amount: draft.amount, method: method,
                                                             accountId: accountId, comment: comment,
                                                             date: draft.transactionDate)
                                },
                                onToggleSelect: {},
                                onLongPress: {}
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
            .navigationTitle(merchant)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { onDismiss() } }
            }
            .onChange(of: vm.draftsForMerchant(merchant).count) { _, newCount in
                if newCount == 0 { onDismiss() }
            }
        }
    }
}

// MARK: - Helper

private func formatElapsed(_ sec: Int) -> String {
    let m = sec / 60, s = sec % 60
    return m > 0 ? "\(m)m \(s)s elapsed" : "\(s)s elapsed"
}
