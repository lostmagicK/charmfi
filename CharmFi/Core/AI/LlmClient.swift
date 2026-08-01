import Foundation

struct LlmRequest: Sendable {
    var model: String
    var systemPrompt: String
    var messages: [AiMessage]
    var maxTokens: Int
    var thinking: Bool
    var tools: [AiTool]? = nil
}

protocol LlmClient: Sendable {
    var provider: AiProvider { get }
    func complete(_ request: LlmRequest) async throws -> String
    func stream(_ request: LlmRequest) -> AsyncThrowingStream<AiStreamChunk, Error>
}
