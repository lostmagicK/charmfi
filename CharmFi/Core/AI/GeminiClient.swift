import Foundation

// MARK: - Wire types

struct GeminiFunctionDeclaration: Encodable {
    var name: String
    var description: String
    var parameters: JSONValue?
}

struct GeminiTool: Encodable {
    var functionDeclarations: [GeminiFunctionDeclaration]
}

struct GeminiFunctionCall: Codable {
    var name: String
    var args: JSONValue?
}

struct GeminiFunctionResponse: Codable {
    var name: String
    var response: JSONValue
}

struct GeminiPart: Codable {
    var text: String? = nil
    var thought: Bool? = nil
    var functionCall: GeminiFunctionCall? = nil
    var functionResponse: GeminiFunctionResponse? = nil
    var thoughtSignature: String? = nil
}

struct GeminiContent: Codable {
    var role: String? = nil
    var parts: [GeminiPart]
}

private struct GeminiThinkingConfig: Encodable {
    var thinkingBudget: Int?
    var includeThoughts: Bool?
    static let adaptiveWithSummary = GeminiThinkingConfig(thinkingBudget: -1, includeThoughts: true)
}

private struct GeminiGenerationConfig: Encodable {
    var maxOutputTokens: Int
    var thinkingConfig: GeminiThinkingConfig?
}

private struct GeminiRequest: Encodable {
    var contents: [GeminiContent]
    var systemInstruction: GeminiContent?
    var generationConfig: GeminiGenerationConfig?
    var tools: [GeminiTool]?
}

private struct GeminiCandidate: Decodable {
    var content: GeminiContent?
    var finishReason: String?
}

private struct GeminiResponse: Decodable {
    var candidates: [GeminiCandidate] = []

    func text() -> String {
        (candidates.first?.content?.parts ?? [])
            .filter { $0.thought != true }
            .map { $0.text ?? "" }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Client

final class GeminiClient: LlmClient {
    let provider: AiProvider = .google
    private let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    func complete(_ request: LlmRequest) async throws -> String {
        let urlRequest = try buildRequest(request, model: request.model, streaming: false)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response, data)
        return try APIClient.decoder.decode(GeminiResponse.self, from: data).text()
    }

    func stream(_ request: LlmRequest) -> AsyncThrowingStream<AiStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let urlRequest = try self.buildRequest(request, model: request.model, streaming: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        try self.validate(response, body)
                    }

                    var finishReason: String? = nil
                    var emittedAny = false
                    var answer = ""
                    var calls: [AiBlock] = []

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, payload != "[DONE]" else { continue }
                        guard let data = payload.data(using: .utf8),
                              let candidate = try? APIClient.decoder.decode(GeminiResponse.self, from: data).candidates.first
                        else { continue }

                        if let fr = candidate.finishReason { finishReason = fr }
                        guard let parts = candidate.content?.parts else { continue }

                        for part in parts {
                            if let call = part.functionCall {
                                let id = "call_\(calls.count)_\(call.name)"
                                let args = call.args ?? .emptyObject
                                var block = AiBlock.toolUse(id: id, name: call.name, input: args)
                                block.signature = part.thoughtSignature
                                calls.append(block)
                                continuation.yield(.toolUse(id: id, name: call.name, input: args))
                            }
                            guard let text = part.text, !text.isEmpty else { continue }
                            if part.thought == true {
                                continuation.yield(.thinking(text))
                            } else {
                                emittedAny = true
                                answer += text
                                continuation.yield(.text(text))
                            }
                        }
                    }

                    let stopReason = !calls.isEmpty ? "tool_use" : finishReason
                    if calls.isEmpty {
                        if finishReason == "SAFETY" || finishReason == "RECITATION", !emittedAny {
                            continuation.yield(.text(AiStreamNotices.refusal))
                        } else if finishReason == "MAX_TOKENS" {
                            continuation.yield(.text(AiStreamNotices.maxTokens))
                        }
                    }
                    var blocks: [AiBlock] = []
                    if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(.text(answer)) }
                    blocks += calls
                    continuation.yield(.turn(blocks: blocks, stopReason: stopReason))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildRequest(_ request: LlmRequest, model: String, streaming: Bool) throws -> URLRequest {
        guard let apiKey = AiKeyStore.shared.apiKey(for: .google), !apiKey.isEmpty else {
            throw MissingAiKeyException(provider: .google)
        }
        let body = GeminiRequest(
            contents: GeminiConversationMapper.toContents(request.messages),
            systemInstruction: GeminiContent(parts: [GeminiPart(text: request.systemPrompt)]),
            generationConfig: GeminiGenerationConfig(
                maxOutputTokens: request.maxTokens,
                thinkingConfig: request.thinking ? .adaptiveWithSummary : nil
            ),
            tools: (request.tools?.isEmpty == false) ? GeminiConversationMapper.toTools(request.tools!) : nil
        )
        let action = streaming ? "streamGenerateContent" : "generateContent"
        var components = URLComponents(url: baseURL.appendingPathComponent("models/\(model):\(action)"), resolvingAgainstBaseURL: false)!
        if streaming { components.queryItems = [URLQueryItem(name: "alt", value: "sse")] }
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
