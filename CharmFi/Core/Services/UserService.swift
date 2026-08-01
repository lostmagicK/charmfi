import Foundation

final class UserService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getProfile() async throws -> UserProfile {
        try await api.request(UserEndpoint.getMe, authState: auth)
    }

    func updateProfile(_ req: UpdateUserRequest) async throws -> UserProfile {
        try await api.request(UserEndpoint.updateMe(req), authState: auth)
    }
}
