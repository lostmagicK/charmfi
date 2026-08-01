import Foundation

final class HouseholdService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getSummary(year: Int? = nil, month: Int? = nil) async throws -> HouseholdSummary {
        try await api.request(HouseholdEndpoint.summary(year: year, month: month), authState: auth)
    }

    func getDaily(year: Int, month: Int) async throws -> [HouseholdDailyPoint] {
        try await api.request(HouseholdEndpoint.daily(year: year, month: month), authState: auth)
    }

    func getExpenses(filters: HouseholdExpenseFilters = .init()) async throws -> PagedResponse<HouseholdExpenseItem> {
        try await api.request(HouseholdEndpoint.expenses(filters), authState: auth)
    }
}
