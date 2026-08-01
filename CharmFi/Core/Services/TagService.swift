import Foundation

final class TagService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getTags() async throws -> [TagResponse] {
        try await api.request(TagEndpoint.list, authState: auth)
    }

    @discardableResult
    func createTag(_ req: TagRequest) async throws -> IdResponse {
        try await api.request(TagEndpoint.create(req), authState: auth)
    }

    func updateTag(id: String, req: TagRequest) async throws {
        try await api.requestVoid(TagEndpoint.update(id: id, body: req), authState: auth)
    }

    func deleteTag(id: String) async throws {
        try await api.requestVoid(TagEndpoint.delete(id: id), authState: auth)
    }
}
