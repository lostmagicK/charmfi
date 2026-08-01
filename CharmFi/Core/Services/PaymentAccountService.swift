import Foundation

final class PaymentAccountService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getAccounts() async throws -> [PaymentAccount] {
        try await api.request(PaymentAccountEndpoint.list, authState: auth)
    }

    func createAccount(_ req: PaymentAccountRequest) async throws -> PaymentAccount {
        try await api.request(PaymentAccountEndpoint.create(req), authState: auth)
    }

    func updateAccount(id: String, req: PaymentAccountRequest) async throws -> PaymentAccount {
        try await api.request(PaymentAccountEndpoint.update(id: id, body: req), authState: auth)
    }

    func deleteAccount(id: String) async throws {
        try await api.requestVoid(PaymentAccountEndpoint.delete(id: id), authState: auth)
    }

    func setDefault(id: String) async throws {
        try await api.requestVoid(PaymentAccountEndpoint.setDefault(id: id), authState: auth)
    }

    func getStats() async throws -> [AccountStats] {
        try await api.request(PaymentAccountEndpoint.stats, authState: auth)
    }

    func getOverview() async throws -> AccountOverview {
        try await api.request(PaymentAccountEndpoint.overview, authState: auth)
    }
}
