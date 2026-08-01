import Foundation

/// Reassembles Anthropic's `content_block_*` SSE deltas into `AiBlock`s, keyed by block index.
/// Thinking blocks (with their signature) must be echoed back to the API verbatim in later turns —
/// dropping or truncating one is the leading cause of 400s in multi-step tool loops.
final class AnthropicStreamAssembler {
    private final class Block {
        var type: String
        var text = ""
        var thinking = ""
        var signature: String? = nil
        var toolId: String? = nil
        var toolName: String? = nil
        var toolJson = ""

        init(type: String) { self.type = type }

        func parsedInput() -> JSONValue {
            let trimmed = toolJson.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let parsed = JSONValue.parse(trimmed) else { return .emptyObject }
            return parsed
        }
    }

    private var blocks: [Int: Block] = [:]
    private var order: [Int] = []
    private(set) var stopReason: String? = nil

    /// Feeds one raw SSE line (still prefixed with "data:") and returns any chunks it produced.
    func accept(_ rawLine: String) throws -> [AiStreamChunk] {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return [] }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return [] }
        guard let obj = JSONValue.parse(payload), let type = obj["type"]?.stringValue else { return [] }

        switch type {
        case "content_block_start": return onBlockStart(obj)
        case "content_block_delta": return onBlockDelta(obj)
        case "content_block_stop": return onBlockStop(obj)
        case "message_delta":
            if let reason = obj["delta"]?["stop_reason"]?.stringValue { stopReason = reason }
            return []
        case "error":
            let msg = obj["error"]?["message"]?.stringValue ?? "stream error"
            throw NetworkError.serverError(0, msg)
        default:
            return []
        }
    }

    private func onBlockStart(_ obj: JSONValue) -> [AiStreamChunk] {
        guard let index = obj["index"]?.intValue, let cb = obj["content_block"] else { return [] }
        let type = cb["type"]?.stringValue ?? "text"
        let block = Block(type: type)
        block.toolId = cb["id"]?.stringValue
        block.toolName = cb["name"]?.stringValue
        if let t = cb["text"]?.stringValue { block.text = t }
        if let t = cb["thinking"]?.stringValue { block.thinking = t }
        blocks[index] = block
        order.append(index)
        return []
    }

    private func onBlockDelta(_ obj: JSONValue) -> [AiStreamChunk] {
        guard let index = obj["index"]?.intValue, let block = blocks[index], let delta = obj["delta"] else { return [] }
        let deltaType = delta["type"]?.stringValue ?? ""
        switch deltaType {
        case "text_delta":
            let t = delta["text"]?.stringValue ?? ""
            block.text += t
            return t.isEmpty ? [] : [.text(t)]
        case "thinking_delta":
            let t = delta["thinking"]?.stringValue ?? ""
            block.thinking += t
            return t.isEmpty ? [] : [.thinking(t)]
        case "signature_delta":
            block.signature = (block.signature ?? "") + (delta["signature"]?.stringValue ?? "")
            return []
        case "input_json_delta":
            block.toolJson += delta["partial_json"]?.stringValue ?? ""
            return []
        default:
            return []
        }
    }

    private func onBlockStop(_ obj: JSONValue) -> [AiStreamChunk] {
        guard let index = obj["index"]?.intValue, let block = blocks[index], block.type == "tool_use" else { return [] }
        guard let id = block.toolId, let name = block.toolName else { return [] }
        return [.toolUse(id: id, name: name, input: block.parsedInput())]
    }

    /// Every block collected so far, in index order — call once the stream ends.
    func turn() -> AiStreamChunk {
        let params: [AiBlock] = order.compactMap { idx in
            guard let block = blocks[idx] else { return nil }
            switch block.type {
            case "text":
                return block.text.isEmpty ? nil : .text(block.text)
            case "thinking":
                return .thinking(block.thinking, signature: block.signature)
            case "tool_use":
                guard let id = block.toolId, let name = block.toolName else { return nil }
                return .toolUse(id: id, name: name, input: block.parsedInput())
            default:
                return nil
            }
        }
        return .turn(blocks: params, stopReason: stopReason)
    }
}
