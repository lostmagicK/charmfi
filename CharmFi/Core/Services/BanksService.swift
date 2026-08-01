import Foundation

final class BanksService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getBanks() async throws -> [Bank] {
        try await api.request(BanksEndpoint.list, authState: auth)
    }
}
