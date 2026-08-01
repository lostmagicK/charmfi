import Foundation
import Observation

@Observable
@MainActor
final class TagsViewModel {
    var tags: [TagResponse] = []
    var isLoading = false
    var error: String?

    private let service: TagService

    init(auth: AuthState) {
        service = TagService(auth: auth)
    }

    var activeTags: [TagResponse] {
        tags.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            tags = try await service.getTags()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func createTag(_ req: TagRequest) async {
        do {
            _ = try await service.createTag(req)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateTag(id: String, req: TagRequest) async {
        do {
            try await service.updateTag(id: id, req: req)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteTag(id: String) async {
        do {
            try await service.deleteTag(id: id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
