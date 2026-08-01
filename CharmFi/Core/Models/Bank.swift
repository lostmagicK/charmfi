import Foundation

struct Bank: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    var color: String?
    var icon: String?
    var senderIds: [String]
    var sortOrder: Int
    var isActive: Bool
    var isSystem: Bool
}
