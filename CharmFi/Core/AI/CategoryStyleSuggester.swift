import Foundation

struct CategoryStyleSuggestion {
    let icon: String?
    let color: String?
}

/// Non-streaming use of the `.categoryStyle` model: given just a category name, asks for an emoji
/// and a hex color as strict JSON. Mirrors Android's `AiRepository.suggestCategoryStyle`.
enum CategoryStyleSuggester {
    static func suggest(name: String) async throws -> CategoryStyleSuggestion {
        let client = try LlmClientFactory.shared.client(for: .categoryStyle)
        let model = LlmClientFactory.shared.model(for: .categoryStyle)
        let request = LlmRequest(
            model: model,
            systemPrompt: """
            Given an expense category name, reply with ONLY a JSON object — no prose, no markdown — \
            of the shape {"icon":"🍽️","color":"#3b82f6"}. "icon" is a single emoji that best represents \
            the category. "color" is a 6-digit hex color that suits it.
            """,
            messages: [AiMessage(role: "user", text: name)],
            maxTokens: 1024,
            thinking: false
        )
        let raw = try await client.complete(request)
        let inner = raw.substringAfterFirst("{").substringBeforeLast("}")
        let jsonSlice = "{" + inner + "}"
        guard let value = JSONValue.parse(jsonSlice) else { return CategoryStyleSuggestion(icon: nil, color: nil) }
        let icon = value["icon"]?.stringValue?.trimmingCharacters(in: .whitespaces)
        let color = value["color"]?.stringValue?.trimmingCharacters(in: .whitespaces)
        return CategoryStyleSuggestion(icon: icon?.isEmpty == false ? icon : nil,
                                        color: color?.isEmpty == false ? color : nil)
    }
}

private extension String {
    /// Everything after the first `needle`, or "" if absent — mirrors Kotlin's `substringAfter`.
    func substringAfterFirst(_ needle: String) -> String {
        guard let r = range(of: needle) else { return "" }
        return String(self[r.upperBound...])
    }
    /// Everything before the last `needle`, or "" if absent — mirrors Kotlin's `substringBeforeLast`.
    func substringBeforeLast(_ needle: String) -> String {
        guard let r = range(of: needle, options: .backwards) else { return "" }
        return String(self[..<r.lowerBound])
    }
}
