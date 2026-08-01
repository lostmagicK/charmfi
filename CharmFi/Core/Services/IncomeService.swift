import Foundation

final class IncomeService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getSources() async throws -> [IncomeSource] {
        try await api.request(IncomeEndpoint.listSources, authState: auth)
    }

    @discardableResult
    func createSource(_ req: IncomeSourceRequest) async throws -> IdResponse {
        try await api.request(IncomeEndpoint.createSource(req), authState: auth)
    }

    func updateSource(id: String, req: IncomeSourceRequest) async throws {
        try await api.requestVoid(IncomeEndpoint.updateSource(id: id, body: req), authState: auth)
    }

    func deleteSource(id: String) async throws {
        try await api.requestVoid(IncomeEndpoint.deleteSource(id: id), authState: auth)
    }

    func getMonth(year: Int? = nil, month: Int? = nil) async throws -> IncomeMonth {
        try await api.request(IncomeEndpoint.month(year: year, month: month), authState: auth)
    }

    func getSummary(months: Int = 12) async throws -> [MonthlyIncomePoint] {
        try await api.request(IncomeEndpoint.summary(months: months), authState: auth)
    }

    @discardableResult
    func createEntry(_ req: IncomeEntryRequest) async throws -> IdResponse {
        try await api.request(IncomeEndpoint.createEntry(req), authState: auth)
    }

    func updateEntry(id: String, req: IncomeEntryUpdateRequest) async throws {
        try await api.requestVoid(IncomeEndpoint.updateEntry(id: id, body: req), authState: auth)
    }

    func deleteEntry(id: String) async throws {
        try await api.requestVoid(IncomeEndpoint.deleteEntry(id: id), authState: auth)
    }
}
