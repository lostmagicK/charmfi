import Foundation

struct MerchantRule: Codable, Identifiable {
    let id: String
    var matchText: String
    var displayName: String?
    var minAmount: Double?
    var maxAmount: Double?
    var categoryId: String?
    var autoSubmit: Bool
    var matchMode: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, matchText, displayName, minAmount, maxAmount, categoryId, autoSubmit, matchMode, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        matchText = try c.decode(String.self, forKey: .matchText)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        minAmount = try c.decodeIfPresent(Double.self, forKey: .minAmount)
        maxAmount = try c.decodeIfPresent(Double.self, forKey: .maxAmount)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        autoSubmit = try c.decodeIfPresent(Bool.self, forKey: .autoSubmit) ?? false
        matchMode = try c.decodeIfPresent(String.self, forKey: .matchMode) ?? "Contains"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    init(id: String, matchText: String, displayName: String?, minAmount: Double?, maxAmount: Double?,
         categoryId: String?, autoSubmit: Bool, matchMode: String = "Contains", createdAt: Date?) {
        self.id = id; self.matchText = matchText; self.displayName = displayName
        self.minAmount = minAmount; self.maxAmount = maxAmount; self.categoryId = categoryId
        self.autoSubmit = autoSubmit; self.matchMode = matchMode; self.createdAt = createdAt
    }
}

struct MerchantRuleRequest: Encodable {
    var matchText: String
    var displayName: String?
    var minAmount: Double?
    var maxAmount: Double?
    var categoryId: String?
    var autoSubmit: Bool = false
    var matchMode: String = "Contains"
}
