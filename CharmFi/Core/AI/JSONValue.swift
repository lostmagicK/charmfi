import Foundation

/// A dynamic JSON value — stands in for Kotlin's `JsonObject` (Gson) for tool schemas, tool-call
/// inputs, and Gemini function args/responses, none of which have a fixed Swift shape.
indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    static let emptyObject = JSONValue.object([:])

    var stringValue: String? { if case .string(let v) = self { v } else { nil } }
    var doubleValue: Double? { if case .number(let v) = self { v } else { nil } }
    var intValue: Int? { doubleValue.map { Int($0) } }
    var boolValue: Bool? { if case .bool(let v) = self { v } else { nil } }
    var objectValue: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    var arrayValue: [JSONValue]? { if case .array(let v) = self { v } else { nil } }

    subscript(key: String) -> JSONValue? { objectValue?[key] }

    /// Compact JSON string, used to send tool-result content as text (Anthropic's `content` field
    /// on a `tool_result` block is a string, not a nested object).
    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func parse(_ string: String) -> JSONValue? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Builds an object schema property: `{"type": type, "description": description}`.
    static func prop(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    /// Builds a JSON-Schema object: `{"type":"object","properties":{...},"required":[...]}`.
    /// `required` is always emitted, even when empty, mirroring Android's `BudgetTools.schema`.
    static func schema(_ props: [(String, JSONValue)], required: [String] = []) -> JSONValue {
        var properties: [String: JSONValue] = [:]
        for (k, v) in props { properties[k] = v }
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) })
        ])
    }
}
