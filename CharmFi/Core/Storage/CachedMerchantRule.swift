import SwiftData
import Foundation

@Model
final class CachedMerchantRule {
    @Attribute(.unique) var ruleId: String
    var matchText: String
    var displayName: String?
    var minAmount: Double?
    var maxAmount: Double?
    var categoryId: String?
    var autoSubmit: Bool
    var matchMode: String = "Contains"
    var cachedAt: Date

    init(from rule: MerchantRule) {
        ruleId = rule.id
        matchText = rule.matchText
        displayName = rule.displayName
        minAmount = rule.minAmount
        maxAmount = rule.maxAmount
        categoryId = rule.categoryId
        autoSubmit = rule.autoSubmit
        matchMode = rule.matchMode
        cachedAt = Date()
    }
}
