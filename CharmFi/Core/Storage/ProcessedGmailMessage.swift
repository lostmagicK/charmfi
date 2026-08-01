import SwiftData
import Foundation

@Model
final class ProcessedGmailMessage {
    @Attribute(.unique) var gmailMessageId: String
    var serverExpenseId: String?
    var processedAt: Date

    init(gmailMessageId: String, serverExpenseId: String? = nil) {
        self.gmailMessageId = gmailMessageId
        self.serverExpenseId = serverExpenseId
        self.processedAt = Date()
    }
}
