import Foundation

final class FamilyGroupService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getGroup() async throws -> FamilyGroup? {
        try? await api.request(FamilyGroupEndpoint.get, authState: auth)
    }

    func createGroup(name: String) async throws -> FamilyGroup {
        try await api.request(FamilyGroupEndpoint.create(name: name), authState: auth)
    }

    func joinGroup(inviteCode: String, displayName: String) async throws -> FamilyGroup {
        try await api.request(FamilyGroupEndpoint.join(inviteCode: inviteCode, displayName: displayName), authState: auth)
    }

    func leaveGroup() async throws {
        try await api.requestVoid(FamilyGroupEndpoint.leave, authState: auth)
    }

    func getSharedExpenses(page: Int = 1) async throws -> PagedResponse<Expense> {
        try await api.request(FamilyGroupEndpoint.sharedExpenses(page: page, pageSize: 20), authState: auth)
    }

    func getBalances() async throws -> [FamilyMemberBalance] {
        try await api.request(FamilyGroupEndpoint.balances, authState: auth)
    }

    func getExpenseLog(userId: String? = nil) async throws -> [SharedExpenseLogEntry] {
        try await api.request(FamilyGroupEndpoint.expenseLog(userId: userId), authState: auth)
    }

    func settle(_ req: SettleRequest) async throws {
        try await api.requestVoid(FamilyGroupEndpoint.settle(req), authState: auth)
    }
}
