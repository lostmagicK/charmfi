import Foundation
import Security

/// BYOK provider API keys and per-use-case model choices, Keychain-backed. Keys go straight to
/// the provider on every request (see AnthropicClient/GeminiClient) and are never sent to the
/// CharmFI backend. Mirrors Android's `AiKeyStore` (EncryptedSharedPreferences there, Keychain here).
final class AiKeyStore: @unchecked Sendable {
    static let shared = AiKeyStore()
    private init() {}

    private enum Key {
        static func apiKey(_ provider: AiProvider) -> String { "ai.apiKey.\(provider.rawValue)" }
        static func model(_ useCase: AiUseCase) -> String { "ai.model.\(useCase.rawValue)" }
        static let categoriesAiEnabled = "ai.categoriesEnabled"
    }

    func apiKey(for provider: AiProvider) -> String? {
        load(key: Key.apiKey(provider))
    }

    func setApiKey(_ value: String?, for provider: AiProvider) {
        guard let value, !value.isEmpty else {
            delete(key: Key.apiKey(provider))
            return
        }
        save(value, key: Key.apiKey(provider))
    }

    func hasKey(for provider: AiProvider) -> Bool {
        apiKey(for: provider)?.isEmpty == false
    }

    func model(for useCase: AiUseCase) -> String? {
        load(key: Key.model(useCase))
    }

    func setModel(_ modelId: String, for useCase: AiUseCase) {
        save(modelId, key: Key.model(useCase))
    }

    var categoriesAiEnabled: Bool {
        get { load(key: Key.categoriesAiEnabled) == "true" }
        set { save(newValue ? "true" : "false", key: Key.categoriesAiEnabled) }
    }

    // MARK: Keychain

    private let service = "in.charmee.charmfi.ai"

    private func save(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service
        ]
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
