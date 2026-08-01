import Foundation

final class MerchantRuleService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getRules() async throws -> [MerchantRule] {
        try await api.request(MerchantRuleEndpoint.list, authState: auth)
    }

    // Server returns 201 with only `{ id }` on create and 204 No Content on update,
    // so there's no full MerchantRule body to decode. The caller reloads from the
    // server afterward, so we only validate the response status here.
    func createRule(_ req: MerchantRuleRequest) async throws {
        try await api.requestVoid(MerchantRuleEndpoint.create(req), authState: auth)
    }

    func updateRule(id: String, req: MerchantRuleRequest) async throws {
        try await api.requestVoid(MerchantRuleEndpoint.update(id: id, body: req), authState: auth)
    }

    func deleteRule(id: String) async throws {
        try await api.requestVoid(MerchantRuleEndpoint.delete(id: id), authState: auth)
    }
}
