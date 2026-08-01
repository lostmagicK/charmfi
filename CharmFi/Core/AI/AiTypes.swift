import Foundation

enum AiProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic = "Anthropic"
    case google = "Google"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .google: "Google AI"
        }
    }

    var keyHint: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .google: "AIza…"
        }
    }

    static func from(wireName: String) -> AiProvider? {
        allCases.first { $0.rawValue == wireName }
    }
}

struct AiModelOption: Identifiable, Equatable {
    let id: String
    let provider: AiProvider
    let label: String
}

enum AiUseCase: String, CaseIterable {
    case insightsChat = "insights_chat"
    case categoryStyle = "category_style"

    var title: String {
        switch self {
        case .insightsChat: "Spending insights chat"
        case .categoryStyle: "Category icon & color"
        }
    }

    var description: String {
        switch self {
        case .insightsChat: "Analyses your expense summary and answers follow-up questions."
        case .categoryStyle: "Suggests an emoji and hex color from a category name."
        }
    }

    var defaultModelId: String {
        switch self {
        case .insightsChat: "claude-opus-5"
        case .categoryStyle: "claude-haiku-4-5"
        }
    }
}

enum AiModels {
    static let seed: [AiModelOption] = [
        AiModelOption(id: "claude-fable-5", provider: .anthropic, label: "Claude Fable 5 — most capable"),
        AiModelOption(id: "claude-opus-5", provider: .anthropic, label: "Claude Opus 5 — highly capable"),
        AiModelOption(id: "claude-sonnet-5", provider: .anthropic, label: "Claude Sonnet 5 — balanced"),
        AiModelOption(id: "claude-haiku-4-5", provider: .anthropic, label: "Claude Haiku 4.5 — fastest, cheapest"),
        AiModelOption(id: "claude-opus-4-8", provider: .anthropic, label: "Claude Opus 4.8 — previous generation"),
        AiModelOption(id: "gemini-3.1-pro-preview", provider: .google, label: "Gemini 3.1 Pro — most capable"),
        AiModelOption(id: "gemini-3.6-flash", provider: .google, label: "Gemini 3.6 Flash — balanced"),
        AiModelOption(id: "gemini-3.5-flash-lite", provider: .google, label: "Gemini 3.5 Flash Lite — fastest, cheapest"),
    ]

    static func guessProvider(_ modelId: String) -> AiProvider {
        modelId.hasPrefix("gemini") ? .google : .anthropic
    }
}

struct AiTool {
    let name: String
    let description: String
    let parameters: JSONValue
}

/// One content block within a message — text, thinking, a tool call, or a tool result. A single
/// flattened shape reused everywhere a block appears, mirroring Android's `AnthropicBlockParam`.
struct AiBlock: Equatable, Codable {
    var type: String
    var text: String? = nil
    var thinking: String? = nil
    var signature: String? = nil
    var id: String? = nil
    var name: String? = nil
    var input: JSONValue? = nil
    var toolUseId: String? = nil
    var content: String? = nil
    var isError: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case type, text, thinking, signature, id, name, input, content
        case toolUseId = "tool_use_id"
        case isError = "is_error"
    }

    init(type: String, text: String? = nil, thinking: String? = nil, signature: String? = nil,
         id: String? = nil, name: String? = nil, input: JSONValue? = nil,
         toolUseId: String? = nil, content: String? = nil, isError: Bool? = nil) {
        self.type = type; self.text = text; self.thinking = thinking; self.signature = signature
        self.id = id; self.name = name; self.input = input
        self.toolUseId = toolUseId; self.content = content; self.isError = isError
    }

    static func text(_ text: String) -> AiBlock { AiBlock(type: "text", text: text) }
    static func thinking(_ thinking: String, signature: String?) -> AiBlock {
        AiBlock(type: "thinking", thinking: thinking, signature: signature)
    }
    static func toolUse(id: String, name: String, input: JSONValue) -> AiBlock {
        AiBlock(type: "tool_use", id: id, name: name, input: input)
    }
    static func toolResult(toolUseId: String, content: String, isError: Bool = false) -> AiBlock {
        AiBlock(type: "tool_result", toolUseId: toolUseId, content: content, isError: isError ? true : nil)
    }
}

struct AiMessage {
    var role: String
    var content: [AiBlock]

    init(role: String, content: [AiBlock]) {
        self.role = role; self.content = content
    }
    init(role: String, text: String) {
        self.role = role; self.content = [.text(text)]
    }

    func text() -> String {
        content.filter { $0.type == "text" }.map { $0.text ?? "" }.joined()
    }
}

enum AiStreamChunk {
    case thinking(String)
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolDone(name: String, summary: String, ok: Bool)
    /// A write-tool call waiting on user approval. `decide` must be called exactly once.
    case confirm(toolName: String, summary: String, decide: (Bool) -> Void)
    case turn(blocks: [AiBlock], stopReason: String?)
    case appended(AiMessage)
}

struct MissingAiKeyException: Error {
    let provider: AiProvider
}
