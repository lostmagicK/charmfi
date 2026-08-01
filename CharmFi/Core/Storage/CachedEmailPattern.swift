import SwiftData
import Foundation

@Model
final class CachedEmailPattern {
    @Attribute(.unique) var patternId: String
    var name: String
    var subjectRegex: String?
    var amountRegex: String
    var merchantRegex: String?
    var dateRegex: String?
    var paymentMethod: String
    var bankName: String?
    var cachedAt: Date

    init(from pattern: EmailPattern) {
        patternId = pattern.id
        name = pattern.name
        subjectRegex = pattern.subjectRegex
        amountRegex = pattern.amountRegex
        merchantRegex = pattern.merchantRegex
        dateRegex = pattern.dateRegex
        paymentMethod = pattern.paymentMethod
        bankName = pattern.bankName
        cachedAt = Date()
    }

    func toEmailPattern() -> EmailPattern {
        EmailPattern(id: patternId, name: name, subjectRegex: subjectRegex,
                     amountRegex: amountRegex, merchantRegex: merchantRegex,
                     dateRegex: dateRegex, paymentMethod: paymentMethod,
                     bankName: bankName, isActive: true, matchCount: 0, createdAt: cachedAt)
    }
}
