import Foundation

final class LlmClientFactory: @unchecked Sendable {
    static let shared = LlmClientFactory()
    private init() {}

    private let anthropicClient = AnthropicClient()
    private let geminiClient = GeminiClient()
    private let keyStore = AiKeyStore.shared
    private let catalog = AiModelCatalogRepository.shared

    func model(for useCase: AiUseCase) -> String {
        keyStore.model(for: useCase) ?? useCase.defaultModelId
    }

    func provider(for useCase: AiUseCase) -> AiProvider {
        catalog.provider(of: model(for: useCase))
    }

    func label(for useCase: AiUseCase) -> String {
        catalog.label(of: model(for: useCase))
    }

    func hasKey(for useCase: AiUseCase) -> Bool {
        keyStore.hasKey(for: provider(for: useCase))
    }

    func client(for useCase: AiUseCase) throws -> LlmClient {
        let provider = provider(for: useCase)
        guard keyStore.hasKey(for: provider) else { throw MissingAiKeyException(provider: provider) }
        switch provider {
        case .anthropic: return anthropicClient
        case .google: return geminiClient
        }
    }
}
