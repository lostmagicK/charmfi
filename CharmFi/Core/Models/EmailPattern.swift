import Foundation

struct EmailPattern: Codable, Identifiable {
    let id: String
    var name: String
    var subjectRegex: String?
    var amountRegex: String
    var merchantRegex: String?
    var dateRegex: String?
    var paymentMethod: String
    var bankName: String?
    var isActive: Bool?       // not returned by GET /email/patterns
    var matchCount: Int
    var createdAt: Date?
}

struct EmailPatternRequest: Encodable {
    var name: String
    var subjectRegex: String?
    var amountRegex: String
    var merchantRegex: String?
    var dateRegex: String?
    var paymentMethod: String
    var bankName: String?
    var isActive: Bool = true   // web always sends this on create/update
}
