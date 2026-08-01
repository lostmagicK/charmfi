import Foundation

enum HTTPMethod: String {
    case GET, POST, PUT, PATCH, DELETE
}

protocol Endpoint {
    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem]? { get }
    var body: (any Encodable)? { get }
}

// MARK: - User

enum UserEndpoint: Endpoint {
    case getMe
    case updateMe(UpdateUserRequest)

    var path: String { "/users/me" }
    var method: HTTPMethod { self == .getMe ? .GET : .PUT }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? {
        if case .updateMe(let req) = self { return req }
        return nil
    }
}

extension UserEndpoint: Equatable {
    static func == (lhs: UserEndpoint, rhs: UserEndpoint) -> Bool {
        switch (lhs, rhs) {
        case (.getMe, .getMe): true
        default: false
        }
    }
}

// MARK: - Expenses

enum ExpenseEndpoint: Endpoint {
    case list(ExpenseFilters)
    case create(CreateExpenseRequest)
    case update(id: String, body: UpdateExpenseRequest)
    case delete(id: String)
    case submit(id: String)
    case batchSubmit(ids: [String])
    case checkDuplicates([DuplicateCandidateRequest])
    case applyMerchantRules
    case setTags(id: String, tagIds: [String])

    var path: String {
        switch self {
        case .list, .create: "/expenses"
        case .update(let id, _), .delete(let id): "/expenses/\(id)"
        case .submit(let id): "/expenses/\(id)/submit"
        case .batchSubmit: "/expenses/batch"
        case .checkDuplicates: "/expenses/check-duplicates"
        case .applyMerchantRules: "/expenses/apply-merchant-rules"
        case .setTags(let id, _): "/expenses/\(id)/tags"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .list: .GET
        case .create, .submit, .batchSubmit, .checkDuplicates, .applyMerchantRules: .POST
        case .update, .setTags: .PUT
        case .delete: .DELETE
        }
    }

    var queryItems: [URLQueryItem]? {
        if case .list(let f) = self { return f.queryItems }
        return nil
    }

    var body: (any Encodable)? {
        switch self {
        case .create(let req): return req
        case .update(_, let req): return req
        case .batchSubmit(let ids): return ["ids": ids]
        case .checkDuplicates(let candidates): return ["candidates": candidates]
        case .setTags(_, let tagIds): return SetTagsRequest(tagIds: tagIds)
        default: return nil
        }
    }
}

// MARK: - Categories

enum CategoryEndpoint: Endpoint {
    case list
    case create(CategoryRequest)
    case update(id: String, body: CategoryRequest)
    case delete(id: String)
    case reorder([ReorderItem])
    case setTags(id: String, tagIds: [String])

    var path: String {
        switch self {
        case .list, .create: "/categories"
        case .update(let id, _), .delete(let id): "/categories/\(id)"
        case .reorder: "/categories/reorder"
        case .setTags(let id, _): "/categories/\(id)/tags"
        }
    }
    var method: HTTPMethod {
        switch self {
        case .list: .GET
        case .create: .POST
        case .update, .setTags: .PUT
        case .delete: .DELETE
        case .reorder: .PATCH
        }
    }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? {
        switch self {
        case .create(let r): return r
        case .update(_, let r): return r
        case .reorder(let items): return items
        case .setTags(_, let tagIds): return SetTagsRequest(tagIds: tagIds)
        default: return nil
        }
    }
}

// MARK: - Banks

enum BanksEndpoint: Endpoint {
    case list

    var path: String { "/banks" }
    var method: HTTPMethod { .GET }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? { nil }
}

// MARK: - Tags

enum TagEndpoint: Endpoint {
    case list
    case create(TagRequest)
    case update(id: String, body: TagRequest)
    case delete(id: String)

    var path: String {
        switch self {
        case .list, .create: "/tags"
        case .update(let id, _), .delete(let id): "/tags/\(id)"
        }
    }
    var method: HTTPMethod {
        switch self {
        case .list: .GET
        case .create: .POST
        case .update: .PUT
        case .delete: .DELETE
        }
    }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? {
        switch self {
        case .create(let r): return r
        case .update(_, let r): return r
        default: return nil
        }
    }
}

// MARK: - Budgets

enum BudgetEndpoint: Endpoint {
    case list(year: Int?, month: Int?)
    case listTrips
    case categorySpending(year: Int?, month: Int?)
    case create(BudgetRequest)
    case update(id: String, body: BudgetRequest)
    case delete(id: String)
    case cycles(budgetId: String)
    case updateCycle(cycleId: String, body: UpdateCycleRequest)
    case createCycle(BudgetCycleCreateRequest)
    case getExcludedCategories
    case setExcludedCategories(categoryIds: [String])

    var path: String {
        switch self {
        case .list, .create: "/budgets"
        case .listTrips: "/budgets/trips"
        case .categorySpending: "/budgets/category-spending"
        case .update(let id, _), .delete(let id): "/budgets/\(id)"
        case .cycles(let id): "/budgets/cycles/\(id)"
        case .updateCycle(let id, _): "/budgets/cycles/\(id)"
        case .createCycle: "/budgets/cycles"
        case .getExcludedCategories, .setExcludedCategories: "/budgets/excluded-categories"
        }
    }
    var method: HTTPMethod {
        switch self {
        case .list, .listTrips, .categorySpending, .cycles, .getExcludedCategories: .GET
        case .create, .createCycle: .POST
        case .update, .updateCycle, .setExcludedCategories: .PUT
        case .delete: .DELETE
        }
    }
    var queryItems: [URLQueryItem]? {
        switch self {
        case .list(let year, let month), .categorySpending(let year, let month):
            var items: [URLQueryItem] = []
            if let year { items.append(.init(name: "year", value: "\(year)")) }
            if let month { items.append(.init(name: "month", value: "\(month)")) }
            return items.isEmpty ? nil : items
        default:
            return nil
        }
    }
    var body: (any Encodable)? {
        switch self {
        case .create(let r): return r
        case .update(_, let r): return r
        case .updateCycle(_, let r): return r
        case .createCycle(let r): return r
        case .setExcludedCategories(let ids): return ["categoryIds": ids]
        default: return nil
        }
    }
}

// MARK: - Payment Accounts

enum PaymentAccountEndpoint: Endpoint {
    case list
    case create(PaymentAccountRequest)
    case update(id: String, body: PaymentAccountRequest)
    case delete(id: String)
    case setDefault(id: String)
    case stats
    case overview

    var path: String {
        switch self {
        case .list, .create: "/payment-accounts"
        case .update(let id, _), .delete(let id): "/payment-accounts/\(id)"
        case .setDefault(let id): "/payment-accounts/\(id)/set-default"
        case .stats: "/payment-accounts/stats"
        case .overview: "/payment-accounts/overview"
        }
    }
    var method: HTTPMethod {
        switch self {
        case .list, .stats, .overview: .GET
        case .create, .setDefault: .POST
        case .update: .PUT
        case .delete: .DELETE
        }
    }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? {
        switch self {
        case .create(let r): return r
        case .update(_, let r): return r
        default: return nil
        }
    }
}

// MARK: - Household

enum HouseholdEndpoint: Endpoint {
    case summary(year: Int?, month: Int?)
    case daily(year: Int, month: Int)
    case expenses(HouseholdExpenseFilters)

    var path: String {
        switch self {
        case .summary: "/household/summary"
        case .daily: "/household/daily"
        case .expenses: "/household/expenses"
        }
    }
    var method: HTTPMethod { .GET }
    var queryItems: [URLQueryItem]? {
        switch self {
        case .summary(let year, let month):
            var items: [URLQueryItem] = []
            if let year { items.append(.init(name: "year", value: "\(year)")) }
            if let month { items.append(.init(name: "month", value: "\(month)")) }
            return items
        case .daily(let y, let m): return [.init(name: "year", value: "\(y)"), .init(name: "month", value: "\(m)")]
        case .expenses(let f): return f.queryItems
        }
    }
    var body: (any Encodable)? { nil }
}

// MARK: - Income

enum IncomeEndpoint: Endpoint {
    case listSources
    case createSource(IncomeSourceRequest)
    case updateSource(id: String, body: IncomeSourceRequest)
    case deleteSource(id: String)
    case month(year: Int?, month: Int?)
    case summary(months: Int)
    case createEntry(IncomeEntryRequest)
    case updateEntry(id: String, body: IncomeEntryUpdateRequest)
    case deleteEntry(id: String)

    var path: String {
        switch self {
        case .listSources, .createSource: "/income/sources"
        case .updateSource(let id, _), .deleteSource(let id): "/income/sources/\(id)"
        case .month: "/income"
        case .summary: "/income/summary"
        case .createEntry: "/income/entries"
        case .updateEntry(let id, _), .deleteEntry(let id): "/income/entries/\(id)"
        }
    }
    var method: HTTPMethod {
        switch self {
        case .listSources, .month, .summary: .GET
        case .createSource, .createEntry: .POST
        case .updateSource, .updateEntry: .PUT
        case .deleteSource, .deleteEntry: .DELETE
        }
    }
    var queryItems: [URLQueryItem]? {
        switch self {
        case .month(let year, let month):
            var items: [URLQueryItem] = []
            if let year { items.append(.init(name: "year", value: "\(year)")) }
            if let month { items.append(.init(name: "month", value: "\(month)")) }
            return items
        case .summary(let months): return [.init(name: "months", value: "\(months)")]
        default: return nil
        }
    }
    var body: (any Encodable)? {
        switch self {
        case .createSource(let r): return r
        case .updateSource(_, let r): return r
        case .createEntry(let r): return r
        case .updateEntry(_, let r): return r
        default: return nil
        }
    }
}

// MARK: - Family Group

enum FamilyGroupEndpoint: Endpoint {
    case get
    case create(name: String)
    case join(inviteCode: String, displayName: String)
    case leave
    case sharedExpenses(page: Int, pageSize: Int)
    case balances
    case expenseLog(userId: String?)
    case settle(SettleRequest)
    case splitShared(id: String)

    var path: String {
        switch self {
        case .get, .create: "/family-group"
        case .join: "/family-group/join"
        case .leave: "/family-group/leave"
        case .sharedExpenses: "/family-group/shared-expenses"
        case .balances: "/family-group/balances"
        case .expenseLog: "/family-group/expense-log"
        case .settle: "/family-group/settle"
        case .splitShared(let id): "/family-group/split-shared/\(id)"
        }
    }
    var method: HTTPMethod {
        switch self {
        case .get, .sharedExpenses, .balances, .expenseLog: .GET
        case .create, .join, .settle, .splitShared: .POST
        case .leave: .DELETE
        }
    }
    var queryItems: [URLQueryItem]? {
        switch self {
        case .sharedExpenses(let p, let ps):
            return [.init(name: "page", value: "\(p)"), .init(name: "pageSize", value: "\(ps)")]
        case .expenseLog(let uid):
            if let uid { return [.init(name: "userId", value: uid)] }
            return nil
        default: return nil
        }
    }
    var body: (any Encodable)? {
        switch self {
        case .create(let name): return ["name": name]
        case .join(let code, let displayName): return ["inviteCode": code, "displayName": displayName]
        case .settle(let req): return req
        default: return nil
        }
    }
}

// MARK: - Merchant Rules

enum MerchantRuleEndpoint: Endpoint {
    case list
    case create(MerchantRuleRequest)
    case update(id: String, body: MerchantRuleRequest)
    case delete(id: String)

    var path: String {
        switch self {
        case .list, .create: "/merchant-rules"
        case .update(let id, _), .delete(let id): "/merchant-rules/\(id)"
        }
    }
    var method: HTTPMethod {
        switch self {
        case .list: .GET
        case .create: .POST
        case .update: .PUT
        case .delete: .DELETE
        }
    }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? {
        switch self {
        case .create(let r): return r
        case .update(_, let r): return r
        default: return nil
        }
    }
}

// MARK: - Email Patterns

enum EmailPatternEndpoint: Endpoint {
    case list
    case create(EmailPatternRequest)
    case update(id: String, body: EmailPatternRequest)
    case delete(id: String)

    var path: String {
        switch self {
        case .list, .create: "/email/patterns"
        case .update(let id, _), .delete(let id): "/email/patterns/\(id)"
        }
    }
    var method: HTTPMethod {
        switch self {
        case .list: .GET
        case .create: .POST
        case .update: .PUT
        case .delete: .DELETE
        }
    }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? {
        switch self {
        case .create(let r): return r
        case .update(_, let r): return r
        default: return nil
        }
    }
}

// MARK: - SMS Patterns (server-managed, no SMS reading on iOS)

enum SmsPatternsEndpoint: Endpoint {
    case list

    var path: String { "/sms/patterns" }
    var method: HTTPMethod { .GET }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? { nil }
}

// MARK: - Paid For

enum PaidForEndpoint: Endpoint {
    case list
    case create(CreateExpenseRequest)

    var path: String { "/paid-for" }
    var method: HTTPMethod { self == .list ? .GET : .POST }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? {
        if case .create(let r) = self { return r }
        return nil
    }
}

extension PaidForEndpoint: Equatable {
    static func == (lhs: PaidForEndpoint, rhs: PaidForEndpoint) -> Bool {
        if case .list = lhs, case .list = rhs { return true }
        return false
    }
}
