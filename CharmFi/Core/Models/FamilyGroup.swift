import Foundation

struct FamilyGroup: Codable, Identifiable {
    let id: String
    var name: String
    var inviteCode: String
    var members: [FamilyMember]
}

struct FamilyMember: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    var displayName: String
    var role: MemberRole
    var joinedAt: Date?          // optional — not present in all API responses

    enum CodingKeys: String, CodingKey {
        case userId, displayName, role, joinedAt
    }
}

enum MemberRole: String, Codable {
    case owner = "Owner"
    case member = "Member"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MemberRole(rawValue: raw) ?? .member
    }
}

struct FamilyMemberBalance: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    var displayName: String
    var iOwe: Double
    var theyOwe: Double
    var netBalance: Double
}

struct SharedExpenseLogEntry: Codable, Identifiable {
    let id: String
    var payerUserId: String
    var payerDisplayName: String
    var recipientUserId: String
    var recipientDisplayName: String
    var amount: Double
    var currency: String
    var merchant: String?
    var paymentMethod: PaymentMethod?
    var accountName: String?
    var accountLast4: String?
    var type: SharedExpenseType
    var relatedExpenseId: String?
    let transactionDate: Date
    var createdAt: Date?
}

enum SharedExpenseType: String, Codable {
    case expense = "Expense"
    case approved = "Approved"
    case deleted = "Deleted"
    case settlement = "Settlement"
}

struct SettleRequest: Encodable {
    var recipientUserId: String
    var amount: Double
    var paymentMethod: PaymentMethod
    var paymentAccountId: String?
    var comment: String?
    var transactionDate: Date
}
