import Foundation
import SwiftData

final class EmailPatternService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getPatterns() async throws -> [EmailPattern] {
        try await api.request(EmailPatternEndpoint.list, authState: auth)
    }

    func createPattern(_ req: EmailPatternRequest) async throws -> EmailPattern {
        try await api.request(EmailPatternEndpoint.create(req), authState: auth)
    }

    func updatePattern(id: String, req: EmailPatternRequest) async throws -> EmailPattern {
        try await api.request(EmailPatternEndpoint.update(id: id, body: req), authState: auth)
    }

    func deletePattern(id: String) async throws {
        try await api.requestVoid(EmailPatternEndpoint.delete(id: id), authState: auth)
    }
}
