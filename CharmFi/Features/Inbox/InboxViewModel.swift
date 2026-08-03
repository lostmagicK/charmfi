import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit

enum InboxState {
    case idle
    case syncing
    case scanning(current: Int, total: Int, found: Int, startedAt: Date)
    case done(found: Int, skipped: Int)
    case error(String)
}

// A draft that collides with a booked expense (`.submitted`, source of truth →
// should be discarded) or with another loaded draft (`.draft`, keep one).
enum DuplicateKind {
    case submitted
    case draft
}

@Observable
@MainActor
final class InboxViewModel: AuthedViewModel {
    // Drafts
    var drafts: [Expense] = []
    var categories: [Category] = []
    var accounts: [PaymentAccount] = []
    var familyMembers: [FamilyMember] = []

    // State
    var state: InboxState = .idle
    var error: String?
    var toast: String?

    // Filters
    var filterMethod: PaymentMethod? = nil
    var filterDate: String? = nil
    var filterCategorized: Bool? = nil
    var showFilters = false
    var searchText = ""

    var filteredDrafts: [Expense] {
        drafts.filter { e in
            (filterMethod == nil || e.paymentMethod == filterMethod) &&
            (filterDate == nil || String(e.transactionDate.description.prefix(10)) == filterDate) &&
            (filterCategorized == nil || (filterCategorized == (e.categoryId != nil))) &&
            (searchText.isEmpty || e.merchant.localizedCaseInsensitiveContains(searchText))
        }
    }

    var availableDates: [String] {
        Array(Set(drafts.map { String($0.transactionDate.description.prefix(10)) })).sorted().reversed()
    }

    // Merchant grouping
    var groupByMerchant = false

    struct MerchantGroup: Identifiable {
        var id: String { merchant }
        let merchant: String
        let drafts: [Expense]
        var count: Int { drafts.count }
        var total: Double { drafts.reduce(0) { $0 + $1.amount } }
        var sharedCategoryId: String? {
            let ids = Set(drafts.map { $0.categoryId })
            return ids.count == 1 ? ids.first ?? nil : nil
        }
    }

    var merchantGroups: [MerchantGroup] {
        let grouped = Dictionary(grouping: filteredDrafts) { $0.merchant.isEmpty ? "Unknown" : $0.merchant }
        return grouped
            .filter { $0.value.count >= 2 }
            .map { MerchantGroup(merchant: $0.key, drafts: $0.value) }
            .sorted { $0.count > $1.count }
    }

    func draftsForMerchant(_ merchant: String) -> [Expense] {
        drafts.filter { $0.merchant.caseInsensitiveCompare(merchant) == .orderedSame }
    }

    // Duplicate detection. submittedDupIds comes from the server (drafts that
    // duplicate an already-booked expense); draftDupIds is derived locally.
    var submittedDupIds: Set<String> = []

    var draftDupIds: Set<String> {
        var groups: [String: [Expense]] = [:]
        for d in drafts {
            if submittedDupIds.contains(d.id) || d.sharedByDisplayName != nil { continue }
            groups[Self.dupKey(d), default: []].append(d)
        }
        var dups: Set<String> = []
        // In each colliding group the first draft is the keeper, the rest are dups.
        for list in groups.values where list.count >= 2 {
            for e in list.dropFirst() { dups.insert(e.id) }
        }
        return dups
    }

    var duplicateCount: Int { submittedDupIds.count + draftDupIds.count }

    func dupKind(_ e: Expense) -> DuplicateKind? {
        if submittedDupIds.contains(e.id) { return .submitted }
        if draftDupIds.contains(e.id) { return .draft }
        return nil
    }

    private static let dupDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func dupKey(_ e: Expense) -> String {
        "\(dupDayFormatter.string(from: e.transactionDate))|\(e.amount)|\(e.paymentMethod.rawValue)"
    }

    // Selection mode
    var selectionMode = false
    var selectedIds: Set<String> = []

    // Submit feedback / bulk progress
    var justSubmittedIds: Set<String> = []
    var isBulkProcessing = false
    var bulkProgress: (current: Int, total: Int)? = nil

    // Gmail state
    var isGmailConnected = false
    var gmailEmail: String?

    // Scan date
    var scanSinceDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()

    private let expenseService: ExpenseService
    private let categoryService: CategoryService
    private let accountService: PaymentAccountService
    private let familyService: FamilyGroupService
    private let patternService: EmailPatternService
    private let gmailAuth = GmailAuthService.shared
    private let gmailFetch = GmailFetchService()
    private let emailParser = EmailParser()
    private var modelContext: ModelContext?

    private let scanQuery = "in:inbox -in:sent subject:(transaction OR payment OR debited OR credited OR spent OR debit OR credit OR bank)"
    private let lastSyncKey = "inbox.gmail.lastSyncDate"

    init(auth: AuthState) {
        expenseService = ExpenseService(auth: auth)
        categoryService = CategoryService(auth: auth)
        accountService = PaymentAccountService(auth: auth)
        familyService = FamilyGroupService(auth: auth)
        patternService = EmailPatternService(auth: auth)
        gmailAuth.restoreSession()
        refreshGmailState()
    }

    func setModelContext(_ ctx: ModelContext) { modelContext = ctx }

    func refreshGmailState() {
        isGmailConnected = gmailAuth.isSignedIn
        gmailEmail = gmailAuth.userEmail
    }

    func load() async {
        error = nil
        do {
            async let draftsResult = expenseService.getDrafts()
            async let cats = categoryService.getCategories()
            async let accts = accountService.getAccounts()
            let (d, c, a) = try await (draftsResult, cats, accts)
            drafts = d.items
            categories = c
            accounts = a
            if let group = try? await familyService.getGroup() {
                familyMembers = group.members
            }
            await refreshDuplicates()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshDuplicates() async {
        do {
            submittedDupIds = Set(try await expenseService.checkDuplicates(drafts))
        } catch {
            submittedDupIds = []
        }
    }

    func removeDuplicates() async {
        let ids = Array(submittedDupIds.union(draftDupIds))
        guard !ids.isEmpty else { return }
        isBulkProcessing = true
        bulkProgress = (0, ids.count)
        defer { isBulkProcessing = false; bulkProgress = nil }
        for (index, id) in ids.enumerated() {
            try? await expenseService.deleteExpense(id: id)
            bulkProgress = (index + 1, ids.count)
        }
        withAnimation(.easeInOut) { drafts.removeAll { ids.contains($0.id) } }
        submittedDupIds.subtract(ids)
        toast = "Removed \(ids.count) duplicate\(ids.count == 1 ? "" : "s")"
    }

    // MARK: - Gmail Sign-In

    func signInGmail() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let vc = scene.windows.first?.rootViewController else { return }
        do {
            _ = try await gmailAuth.signIn(presenting: vc)
            refreshGmailState()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOutGmail() { gmailAuth.signOut(); refreshGmailState() }

    // MARK: - Email Scan

    func scanEmail(since: Date? = nil) async {
        guard isGmailConnected else { self.error = "Connect Gmail first"; return }
        let sinceDate = since ?? UserDefaults.standard.object(forKey: lastSyncKey) as? Date ?? scanSinceDate
        state = .scanning(current: 0, total: 0, found: 0, startedAt: Date())

        do {
            let token = try await gmailAuth.refreshTokenIfNeeded()
            let patterns = try await patternService.getPatterns()
            guard !patterns.isEmpty else {
                state = .error("No email patterns configured. Add patterns in More → Email Patterns.")
                return
            }

            state = .scanning(current: 0, total: 0, found: 0, startedAt: Date())
            let messageIds = try await gmailFetch.listMessageIds(accessToken: token, query: scanQuery, sinceDate: sinceDate)

            var found = 0
            var skipped = 0

            for (idx, msgId) in messageIds.enumerated() {
                if case .scanning(_, _, let f, let start) = state {
                    state = .scanning(current: idx + 1, total: messageIds.count, found: f, startedAt: start)
                }
                if isDuplicate(gmailMessageId: msgId) { skipped += 1; continue }

                do {
                    let message = try await gmailFetch.getMessage(accessToken: token, messageId: msgId)
                    if let parsed = emailParser.parse(message: message, patterns: patterns) {
                        let req = CreateExpenseRequest(
                            amount: parsed.amount, merchant: parsed.merchant,
                            paymentMethod: parsed.paymentMethod,
                            transactionDate: parsed.transactionDate,
                            source: .email, status: .draft,
                            rawSmsText: String(message.body.prefix(500))
                        )
                        let expense = try await expenseService.createExpense(req)
                        saveProcessed(gmailMessageId: msgId, serverExpenseId: expense.id)
                        found += 1
                        if case .scanning(let c, let t, _, let start) = state {
                            state = .scanning(current: c, total: t, found: found, startedAt: start)
                        }
                    } else {
                        saveProcessed(gmailMessageId: msgId, serverExpenseId: nil)
                        skipped += 1
                    }
                } catch { skipped += 1 }
            }

            UserDefaults.standard.set(Date(), forKey: lastSyncKey)
            state = .done(found: found, skipped: skipped)
            await load()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    var lastSyncDate: Date? { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }

    // MARK: - Draft actions

    func updateDraft(id: String, req: UpdateExpenseRequest) async {
        do {
            let updated = try await expenseService.updateExpense(id: id, req: req)
            if let idx = drafts.firstIndex(where: { $0.id == id }) { drafts[idx] = updated }
        } catch {}
    }

    func applyCategoryToMerchant(_ merchant: String, categoryId: String?) async {
        for draft in draftsForMerchant(merchant) {
            let req = UpdateExpenseRequest(
                merchant: draft.merchant, paymentMethod: draft.paymentMethod,
                comment: draft.comment, categoryId: categoryId,
                paymentAccountId: draft.paymentAccountId
            )
            await updateDraft(id: draft.id, req: req)
        }
    }

    func submitMerchantGroup(_ merchant: String) async {
        let ids = draftsForMerchant(merchant).map(\.id)
        guard !ids.isEmpty else { return }
        isBulkProcessing = true
        defer { isBulkProcessing = false }
        do {
            try await expenseService.batchSubmit(ids: ids)
            justSubmittedIds.formUnion(ids)
            toast = "Submitted \(ids.count) expense\(ids.count == 1 ? "" : "s")"
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeInOut) { drafts.removeAll { ids.contains($0.id) } }
            justSubmittedIds.subtract(ids)
        } catch { self.error = error.localizedDescription }
    }

    func approveDraft(id: String) async {
        do {
            try await expenseService.submitExpense(id: id)
            justSubmittedIds.insert(id)
            toast = "Expense submitted"
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeInOut) { drafts.removeAll { $0.id == id } }
            justSubmittedIds.remove(id)
        } catch { self.error = error.localizedDescription }
    }

    /// "For Someone + Repayment" drafts record an actual settlement against the family balance,
    /// not an ordinary expense — the draft itself is discarded once the settlement is recorded.
    func settleFromDraft(draftId: String, recipientUserId: String, amount: Double,
                         method: PaymentMethod, accountId: String?, comment: String?, date: Date) async {
        do {
            try await familyService.settle(SettleRequest(
                recipientUserId: recipientUserId, amount: amount, paymentMethod: method,
                paymentAccountId: accountId, comment: comment, transactionDate: date))
            try await expenseService.deleteExpense(id: draftId)
            justSubmittedIds.insert(draftId)
            toast = "Settled"
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeInOut) { drafts.removeAll { $0.id == draftId } }
            justSubmittedIds.remove(draftId)
        } catch { self.error = error.localizedDescription }
    }

    func splitDraft(draft: Expense, splits: [SplitItem]) async {
        do {
            for split in splits {
                guard let amount = Double(split.amount), amount > 0 else { continue }
                let req = CreateExpenseRequest(
                    amount: amount,
                    merchant: split.merchant.isEmpty ? draft.merchant : split.merchant,
                    paymentMethod: draft.paymentMethod,
                    transactionDate: draft.transactionDate,
                    source: draft.source ?? .manual,
                    status: .draft,
                    comment: draft.comment,
                    categoryId: split.categoryId ?? draft.categoryId,
                    paymentAccountId: draft.paymentAccountId
                )
                _ = try await expenseService.createExpense(req)
            }
            try await expenseService.deleteExpense(id: draft.id)
            withAnimation(.easeInOut) { drafts.removeAll { $0.id == draft.id } }
            toast = "Split into \(splits.count) drafts"
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func discardDraft(id: String) async {
        do {
            try await expenseService.deleteExpense(id: id)
            withAnimation(.easeInOut) { drafts.removeAll { $0.id == id } }
        } catch { self.error = error.localizedDescription }
    }

    // MARK: - Selection mode

    func enterSelectionMode() { selectionMode = true }
    func exitSelectionMode() { selectionMode = false; selectedIds.removeAll() }
    func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    func selectAll() { selectedIds = Set(filteredDrafts.map(\.id)) }
    func selectNone() { selectedIds.removeAll() }

    func submitSelected() async {
        let ids = Array(selectedIds)
        isBulkProcessing = true
        defer { isBulkProcessing = false }
        do {
            try await expenseService.batchSubmit(ids: ids)
            justSubmittedIds.formUnion(ids)
            toast = "Submitted \(ids.count) expense\(ids.count == 1 ? "" : "s")"
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeInOut) { drafts.removeAll { ids.contains($0.id) } }
            justSubmittedIds.subtract(ids)
            exitSelectionMode()
        } catch { self.error = error.localizedDescription }
    }

    func applyCategoryToSelected(_ categoryId: String?) async {
        let ids = selectedIds
        for draft in drafts where ids.contains(draft.id) {
            let req = UpdateExpenseRequest(
                merchant: draft.merchant, paymentMethod: draft.paymentMethod,
                comment: draft.comment, categoryId: categoryId,
                paymentAccountId: draft.paymentAccountId
            )
            await updateDraft(id: draft.id, req: req)
        }
        toast = "Category applied to \(ids.count) expense\(ids.count == 1 ? "" : "s")"
    }

    func discardSelected() async {
        let ids = Array(selectedIds)
        isBulkProcessing = true
        bulkProgress = (0, ids.count)
        defer { isBulkProcessing = false; bulkProgress = nil }
        for (index, id) in ids.enumerated() {
            try? await expenseService.deleteExpense(id: id)
            bulkProgress = (index + 1, ids.count)
        }
        withAnimation(.easeInOut) { drafts.removeAll { ids.contains($0.id) } }
        exitSelectionMode()
    }

    // MARK: - Filters

    func clearFilters() { filterMethod = nil; filterDate = nil; filterCategorized = nil }

    // MARK: - PDF (server-side)

    struct PdfImportResult {
        let success: Bool
        let created: Int
        let message: String
    }

    // Uploads the PDF to the backend, which runs the PdfPig-based HDFC parser and
    // creates the draft expenses. Preferred over on-device parsing: PDFKit can't
    // reliably reconstruct HDFC's multi-line tabular layout.
    //
    // On success the imported drafts are loaded and a `.done` banner is surfaced so
    // the Inbox reflects the import the moment the sheet dismisses. Failures (wrong
    // password, unsupported format) are returned so the sheet can stay open and let
    // the user correct and retry.
    func importPdf(fileURL: URL, password: String?) async -> PdfImportResult {
        do {
            let result = try await expenseService.uploadPdf(
                fileURL: fileURL,
                password: password,
                bankHint: "HDFC"
            )
            await load()
            state = .done(found: result.created, skipped: 0)
            return PdfImportResult(success: true, created: result.created, message: result.message)
        } catch {
            return PdfImportResult(success: false, created: 0, message: error.localizedDescription)
        }
    }

    // MARK: - PDF (on-device fallback)

    func parsePdfOnDevice(fileURL: URL, password: String?) async -> (message: String, extractedText: String?) {
        let parser = PDFExpenseParser()
        let rawText = try? parser.extractText(url: fileURL, password: password)
        let patterns = (try? await patternService.getPatterns()) ?? []
        let parsed: [ParsedExpense]
        do {
            parsed = try parser.parse(url: fileURL, password: password, patterns: patterns)
        } catch {
            return (error.localizedDescription, rawText)
        }

        var created = 0; var failed = 0
        for expense in parsed {
            let req = CreateExpenseRequest(
                amount: expense.amount,
                merchant: expense.merchant,
                paymentMethod: expense.paymentMethod,
                transactionDate: expense.transactionDate,
                source: .pdf,
                status: .draft
            )
            do { _ = try await expenseService.createExpense(req); created += 1 }
            catch { failed += 1 }
        }
        await load()
        let failNote = failed > 0 ? ", \(failed) failed" : ""
        return ("\(created) draft expense(s) created\(failNote)", rawText)
    }

    // MARK: - SwiftData helpers

    private func isDuplicate(gmailMessageId: String) -> Bool {
        guard let ctx = modelContext else { return false }
        let desc = FetchDescriptor<ProcessedGmailMessage>(
            predicate: #Predicate { $0.gmailMessageId == gmailMessageId })
        return (try? ctx.fetch(desc))?.isEmpty == false
    }

    private func saveProcessed(gmailMessageId: String, serverExpenseId: String?) {
        guard let ctx = modelContext else { return }
        ctx.insert(ProcessedGmailMessage(gmailMessageId: gmailMessageId, serverExpenseId: serverExpenseId))
        try? ctx.save()
    }
}
