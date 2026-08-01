import Foundation

/// Syncs the admin-managed model catalog from the backend, caching it so ViewModels and
/// interceptor-equivalents can look models up synchronously between syncs. Falls back to
/// `AiModels.seed` before the first successful sync. Cached to `UserDefaults` (not SwiftData —
/// this list is small, replaces wholesale on every sync, and has no relationships worth a schema).
final class AiModelCatalogRepository: @unchecked Sendable {
    static let shared = AiModelCatalogRepository()
    private init() {
        if let cached = Self.loadCached(), !cached.isEmpty { cachedModels = cached }
    }

    private(set) var cachedModels: [AiModelOption] = AiModels.seed

    private static let defaultsKey = "ai.modelCatalog"

    @discardableResult
    func sync(auth: AuthState) async -> [AiModelOption] {
        do {
            let response: [AiModelCatalogResponse] = try await APIClient.shared.request(AiModelsEndpoint.list, authState: auth)
            let options = response.compactMap { $0.toOption() }
            if !options.isEmpty {
                cachedModels = options
                Self.saveCached(options)
            }
        } catch {
            // Keep whatever was cached (seed or a previous sync) — a catalog fetch failure
            // shouldn't block chat from working with the default models.
        }
        return cachedModels
    }

    func provider(of modelId: String) -> AiProvider {
        cachedModels.first { $0.id == modelId }?.provider ?? AiModels.guessProvider(modelId)
    }

    func label(of modelId: String) -> String {
        cachedModels.first { $0.id == modelId }?.label ?? modelId
    }

    private static func saveCached(_ options: [AiModelOption]) {
        let encoded = options.map { ["id": $0.id, "provider": $0.provider.rawValue, "label": $0.label] }
        UserDefaults.standard.set(encoded, forKey: defaultsKey)
    }

    private static func loadCached() -> [AiModelOption]? {
        guard let raw = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: String]] else { return nil }
        return raw.compactMap { dict in
            guard let id = dict["id"], let providerRaw = dict["provider"], let label = dict["label"],
                  let provider = AiProvider(rawValue: providerRaw) else { return nil }
            return AiModelOption(id: id, provider: provider, label: label)
        }
    }
}

private struct AiModelCatalogResponse: Decodable {
    let modelId: String
    let provider: String
    let label: String
}

private extension AiModelCatalogResponse {
    func toOption() -> AiModelOption? {
        guard let provider = AiProvider.from(wireName: provider) else { return nil }
        return AiModelOption(id: modelId, provider: provider, label: label)
    }
}

private enum AiModelsEndpoint: Endpoint {
    case list

    var path: String { "/ai-models" }
    var method: HTTPMethod { .GET }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable)? { nil }
}
