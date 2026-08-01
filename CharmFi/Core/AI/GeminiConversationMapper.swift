import Foundation

/// Maps the provider-agnostic `AiMessage`/`AiBlock` history to Gemini's `contents`/`tools` shape.
/// Gemini has no `tool_result` concept — a result must be addressed by function *name*, not the
/// call id Anthropic uses, so this resolves names from the `tool_use` blocks seen earlier in the
/// same history.
enum GeminiConversationMapper {
    static func toTools(_ tools: [AiTool]) -> [GeminiTool] {
        [GeminiTool(functionDeclarations: tools.map { tool in
            let hasProperties: Bool
            if case .object(let props)? = tool.parameters["properties"], !props.isEmpty { hasProperties = true }
            else { hasProperties = false }
            return GeminiFunctionDeclaration(name: tool.name, description: tool.description,
                                              parameters: hasProperties ? tool.parameters : nil)
        })]
    }

    static func toContents(_ messages: [AiMessage]) -> [GeminiContent] {
        var nameById: [String: String] = [:]
        for message in messages {
            for block in message.content where block.type == "tool_use" {
                if let id = block.id, let name = block.name { nameById[id] = name }
            }
        }
        return messages.compactMap { message in
            let parts = message.content.compactMap { toPart($0, nameById: nameById) }
            guard !parts.isEmpty else { return nil }
            return GeminiContent(role: message.role == "assistant" ? "model" : "user", parts: parts)
        }
    }

    private static func toPart(_ block: AiBlock, nameById: [String: String]) -> GeminiPart? {
        switch block.type {
        case "text":
            guard let text = block.text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return GeminiPart(text: text)
        case "thinking":
            return nil
        case "tool_use":
            return GeminiPart(functionCall: GeminiFunctionCall(name: block.name ?? "", args: block.input ?? .emptyObject),
                               thoughtSignature: block.signature)
        case "tool_result":
            let name = nameById[block.toolUseId ?? ""] ?? (block.toolUseId ?? "")
            return GeminiPart(functionResponse: GeminiFunctionResponse(
                name: name, response: responseObject(block.content ?? "", isError: block.isError == true)))
        default:
            return nil
        }
    }

    private static func responseObject(_ content: String, isError: Bool) -> JSONValue {
        if isError { return .object(["error": .string(content)]) }
        if let parsed = JSONValue.parse(content) {
            if case .object = parsed { return parsed }
            return .object(["result": parsed])
        }
        return .object(["result": .string(content)])
    }
}
