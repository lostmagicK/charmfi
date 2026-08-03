import Foundation

final class CategoryService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getCategories() async throws -> [Category] {
        try await api.request(CategoryEndpoint.list, authState: auth)
    }

    /// Returns the new id — the endpoint answers `{ "id": ... }`, not the category. Decoding it
    /// as a `Category` threw "the data couldn't be read because it is missing" on every
    /// successful create, *after* the row had already been committed.
    func createCategory(_ req: CategoryRequest) async throws -> String {
        let res: IdResponse = try await api.request(CategoryEndpoint.create(req), authState: auth)
        return res.id
    }

    /// 204 No Content — decoding a body here would fail every successful update.
    func updateCategory(id: String, req: CategoryRequest) async throws {
        try await api.requestVoid(CategoryEndpoint.update(id: id, body: req), authState: auth)
    }

    func deleteCategory(id: String) async throws {
        try await api.requestVoid(CategoryEndpoint.delete(id: id), authState: auth)
    }

    func reorderCategories(_ items: [ReorderItem]) async throws {
        try await api.requestVoid(CategoryEndpoint.reorder(items), authState: auth)
    }

    /// Whole-set replace — always send the complete desired tag list, not a delta. Locked
    /// (admin-pinned) tags aren't affected since the caller should only ever pass `ownTagIds()`.
    func setTags(id: String, tagIds: [String]) async throws {
        try await api.requestVoid(CategoryEndpoint.setTags(id: id, tagIds: tagIds), authState: auth)
    }
}
