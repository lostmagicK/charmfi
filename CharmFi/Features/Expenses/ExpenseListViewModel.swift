import Foundation
import Observation

enum DatePreset: String, CaseIterable {
    case thisMonth   = "This Month"
    case lastMonth   = "Last Month"
    case last3Months = "3 Months"
    case thisYear    = "This Year"
    case all         = "All Time"
}

@Observable
@MainActor
final class ExpenseListViewModel: AuthedViewModel {
    var expenses: [Expense] = []
    var isLoading = false
    var error: String?
    var toast: String?

    // Pagination
    var page = 1
    var total = 0
    var totalAmount: Double = 0
    let pageSize = 20
    var totalPages: Int { max(1, Int(ceil(Double(total) / Double(pageSize)))) }

    // Filters
    var datePreset: DatePreset = .thisMonth
    var searchText = ""
    var selectedCategoryId: String? = nil
    var selectedMethod: PaymentMethod? = nil
    var showFilters = false

    // Supporting data
    var categories: [Category] = []
    var accounts: [PaymentAccount] = []
    var familyMembers: [FamilyMember] = []
    var allTags: [TagResponse] = []

    private let expenseService: ExpenseService
    private let categoryService: CategoryService
    private let accountService: PaymentAccountService
    private let familyService: FamilyGroupService
    private let tagService: TagService

    init(auth: AuthState) {
        expenseService = ExpenseService(auth: auth)
        categoryService = CategoryService(auth: auth)
        accountService = PaymentAccountService(auth: auth)
        familyService = FamilyGroupService(auth: auth)
        tagService = TagService(auth: auth)
    }

    func initialLoad() async {
        async let cats = categoryService.getCategories()
        async let accts = accountService.getAccounts()
        async let tags = tagService.getTags()
        do {
            let (loadedCats, loadedAccts, loadedTags) = try await (cats, accts, tags)
            categories = loadedCats
            accounts = loadedAccts
            allTags = loadedTags
        } catch {
            // These back the filter chips and the add/edit pickers. Silently empty ones look like
            // "you have no categories" rather than "the fetch failed".
            self.error = error.localizedDescription
        }
        // Not every user is in a family group — a failure here just means no split/settle options.
        if let members = try? await familyService.getGroup() {
            familyMembers = members.members
        }
        await load()
    }

    func createTag(_ req: TagRequest) async -> TagResponse? {
        guard let created = try? await tagService.createTag(req) else { return nil }
        let tag = TagResponse(id: created.id, name: req.name, color: req.color, isGlobal: false,
                               isOwn: true, isActive: true, sortOrder: req.sortOrder ?? 0)
        allTags.append(tag)
        return tag
    }

    func setExpenseTags(id: String, tagIds: [String]) async {
        do {
            try await expenseService.setTags(id: id, tagIds: tagIds)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Records an actual settlement against a family balance — distinct from creating an ordinary
    /// expense, so the family-group ledger (not just this device's expense list) reflects it.
    func settle(recipientUserId: String, amount: Double, method: PaymentMethod,
                accountId: String?, comment: String?, date: Date) async {
        do {
            try await familyService.settle(SettleRequest(
                recipientUserId: recipientUserId, amount: amount, paymentMethod: method,
                paymentAccountId: accountId, comment: comment, transactionDate: date))
            toast = "Settled"
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func load() async {
        isLoading = true
        error = nil
        var f = ExpenseFilters()
        f.status = .submitted
        f.page = page
        f.pageSize = pageSize
        f.search = searchText.isEmpty ? nil : searchText
        f.categoryId = selectedCategoryId
        f.paymentMethod = selectedMethod

        let (from, to) = dateRange()
        f.from = from
        f.to = to

        do {
            let result = try await expenseService.getExpenses(filters: f)
            expenses = result.items
            total = result.total
            totalAmount = result.totalAmount ?? result.items.map(\.amount).reduce(0, +)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func applyPreset(_ preset: DatePreset) {
        datePreset = preset
        page = 1
        Task { await load() }
    }

    func search(_ q: String) {
        searchText = q
        page = 1
        Task { await load() }
    }

    func filterCategory(_ id: String?) {
        selectedCategoryId = id
        page = 1
        Task { await load() }
    }

    func filterMethod(_ method: PaymentMethod?) {
        selectedMethod = method
        page = 1
        Task { await load() }
    }

    func clearFilters() {
        searchText = ""
        selectedCategoryId = nil
        selectedMethod = nil
        page = 1
        Task { await load() }
    }

    func nextPage() { guard page < totalPages else { return }; page += 1; Task { await load() } }
    func prevPage() { guard page > 1 else { return }; page -= 1; Task { await load() } }
    func goToPage(_ p: Int) { page = p; Task { await load() } }

    func deleteExpense(id: String) async {
        do {
            try await expenseService.deleteExpense(id: id)
            toast = "Expense deleted"
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateExpense(id: String, merchant: String, comment: String?,
                       categoryId: String?, paymentMethod: PaymentMethod) async {
        let req = UpdateExpenseRequest(merchant: merchant, paymentMethod: paymentMethod,
                                       comment: comment, categoryId: categoryId)
        do {
            _ = try await expenseService.updateExpense(id: id, req: req)
            toast = "Expense updated"
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createExpense(amount: Double, merchant: String, paymentMethod: PaymentMethod,
                       date: Date, comment: String?, categoryId: String?,
                       accountId: String?, paidForUserId: String?) async {
        let req = CreateExpenseRequest(
            amount: amount, merchant: merchant, paymentMethod: paymentMethod,
            transactionDate: date, source: .manual, status: .submitted,
            comment: comment, categoryId: categoryId,
            paymentAccountId: accountId, sharedByUserId: paidForUserId
        )
        do {
            _ = try await expenseService.createExpense(req)
            toast = paidForUserId != nil ? "Sent to family member" : "Expense added"
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedCategoryId != nil || selectedMethod != nil
    }

    private func dateRange() -> (Date?, Date?) {
        let cal = Calendar.current
        switch datePreset {
        case .thisMonth:
            return (Date.startOfThisMonth, Date.startOfNextMonth)
        case .lastMonth:
            return (Date.startOfLastMonth, Date.startOfThisMonth)
        case .last3Months:
            return (cal.date(byAdding: .month, value: -2, to: Date.startOfThisMonth), Date.startOfNextMonth)
        case .thisYear:
            return (Date.startOfThisYear, Date.startOfNextYear)
        case .all:
            return (nil, nil)
        }
    }
}
