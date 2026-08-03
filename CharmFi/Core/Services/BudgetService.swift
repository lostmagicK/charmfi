import Foundation

final class BudgetService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getBudgets(year: Int? = nil, month: Int? = nil) async throws -> [Budget] {
        try await api.request(BudgetEndpoint.list(year: year, month: month), authState: auth)
    }

    func getTripBudgets() async throws -> [Budget] {
        try await api.request(BudgetEndpoint.listTrips, authState: auth)
    }

    func getCategorySpending(year: Int? = nil, month: Int? = nil) async throws -> [String: Double] {
        try await api.request(BudgetEndpoint.categorySpending(year: year, month: month), authState: auth)
    }

    /// The server answers a create with `{ "id": … }`, not the budget itself — callers refetch.
    @discardableResult
    func createBudget(_ req: BudgetRequest) async throws -> String {
        let res: IdResponse = try await api.request(BudgetEndpoint.create(req), authState: auth)
        return res.id
    }

    /// 204 No Content — decoding a body here would fail every successful update.
    func updateBudget(id: String, req: BudgetRequest) async throws {
        try await api.requestVoid(BudgetEndpoint.update(id: id, body: req), authState: auth)
    }

    func deleteBudget(id: String) async throws {
        try await api.requestVoid(BudgetEndpoint.delete(id: id), authState: auth)
    }

    func getCycles(budgetId: String) async throws -> [BudgetCycle] {
        try await api.request(BudgetEndpoint.cycles(budgetId: budgetId), authState: auth)
    }

    func updateCycle(cycleId: String, amount: Double) async throws {
        try await api.requestVoid(BudgetEndpoint.updateCycle(cycleId: cycleId, body: .init(baseAmount: amount)), authState: auth)
    }

    func upsertCycle(budgetId: String, year: Int, month: Int, amount: Double) async throws {
        try await api.requestVoid(
            BudgetEndpoint.createCycle(.init(budgetId: budgetId, year: year, month: month, baseAmount: amount)),
            authState: auth
        )
    }

    func getExcludedCategories() async throws -> [String] {
        try await api.request(BudgetEndpoint.getExcludedCategories, authState: auth)
    }

    /// Complete set of root category ids opted out of monthly budgeting — the server expands
    /// descendants, so this always replaces the whole set, never a delta.
    func setExcludedCategories(_ categoryIds: [String]) async throws {
        try await api.requestVoid(BudgetEndpoint.setExcludedCategories(categoryIds: categoryIds), authState: auth)
    }
}
