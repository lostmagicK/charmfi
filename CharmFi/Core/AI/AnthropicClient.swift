import Foundation

private struct AnthropicThinking: Encodable {
    var type: String
    var display: String? = nil
    static let disabled = AnthropicThinking(type: "disabled")
    static let adaptiveSummarized = AnthropicThinking(type: "adaptive", display: "summarized")
}

private struct AnthropicTool: Encodable {
    var name: String
    var description: String
    var inputSchema: JSONValue
    enum CodingKeys: String, CodingKey { case name, description; case inputSchema = "input_schema" }
}

private struct AnthropicMessage: Encodable {
    var role: String
    var content: [AiBlock]
}

private struct AnthropicRequest: Encodable {
    var model: String
    var maxTokens: Int
    var system: String?
    var messages: [AnthropicMessage]
    var stream: Bool?
    var thinking: AnthropicThinking?
    var tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, stream, thinking, tools
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicResponse: Decodable {
    var stopReason: String?
    var content: [AiBlock]
    enum CodingKeys: String, CodingKey { case content; case stopReason = "stop_reason" }

    func text() -> String {
        content.filter { $0.type == "text" }.map { $0.text ?? "" }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Cut off / declined messages shared verbatim with GeminiClient so the chat reads consistently
/// regardless of which provider produced them.
enum AiStreamNotices {
    static let refusal = "The request was declined by the model's safety filters. Try rephrasing your question."
    static let maxTokens = "\n\n…(response was cut off — send \"continue\" for the rest.)"
}

final class AnthropicClient: LlmClient {
    let provider: AiProvider = .anthropic
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    func complete(_ request: LlmRequest) async throws -> String {
        let urlRequest = try buildRequest(request, stream: false)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response, data)
        let decoded = try APIClient.decoder.decode(AnthropicResponse.self, from: data)
        return decoded.text()
    }

    func stream(_ request: LlmRequest) -> AsyncThrowingStream<AiStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let urlRequest = try self.buildRequest(request, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        try self.validate(response, body)
                    }
                    let assembler = AnthropicStreamAssembler()
                    var emittedText = false
                    for try await line in bytes.lines {
                        for chunk in try assembler.accept(line) {
                            if case .text = chunk { emittedText = true }
                            continuation.yield(chunk)
                        }
                    }
                    if assembler.stopReason != "tool_use" {
                        if assembler.stopReason == "refusal" && !emittedText {
                            continuation.yield(.text(AiStreamNotices.refusal))
                        } else if assembler.stopReason == "max_tokens" {
                            continuation.yield(.text(AiStreamNotices.maxTokens))
                        }
                    }
                    continuation.yield(assembler.turn())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildRequest(_ request: LlmRequest, stream: Bool) throws -> URLRequest {
        guard let apiKey = AiKeyStore.shared.apiKey(for: .anthropic), !apiKey.isEmpty else {
            throw MissingAiKeyException(provider: .anthropic)
        }
        let body = AnthropicRequest(
            model: request.model,
            maxTokens: request.maxTokens,
            system: request.systemPrompt,
            messages: request.messages.map { AnthropicMessage(role: $0.role, content: $0.content) },
            stream: stream ? true : nil,
            thinking: request.thinking ? .adaptiveSummarized : .disabled,
            tools: (request.tools?.isEmpty == false) ? request.tools!.map {
                AnthropicTool(name: $0.name, description: $0.description, inputSchema: $0.parameters)
            } : nil
        )
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    private func validate(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard !(200...299).contains(http.statusCode) else { return }
        let message = JSONValue.parse(String(data: data, encoding: .utf8) ?? "")?["error"]?["message"]?.stringValue
        throw AiHttpError(statusCode: http.statusCode, providerMessage: message)
    }
}

/// An HTTP failure from a provider call — carries the status code and the provider's own error
/// message (both providers use `{"error":{"message": "..."}}`) so `AiErrors` can format it.
struct AiHttpError: Error {
    let statusCode: Int
    let providerMessage: String?
}
