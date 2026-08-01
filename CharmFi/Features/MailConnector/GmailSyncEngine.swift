import Foundation
import SwiftData

/// Headless Gmail → expense scan pipeline shared by the Mail Connector screen (foreground)
/// and `BackgroundSyncManager` (background refresh). No UI/UIKit dependency: it takes an
/// `AuthState` and `ModelContext` and reports progress/failures via optional callbacks.
@MainActor
struct GmailSyncEngine {
    static let lastSyncKey = "gmail.lastSyncDate"

    private let gmailAuth = GmailAuthService.shared
    private let gmailFetch = GmailFetchService()
    private let emailParser = EmailParser()

    // Mirrors the backend's Gmail search so iOS scans the same set of messages.
    private let syncQuery = "in:inbox -in:sent (subject:debited OR subject:debit OR subject:transaction OR subject:payment OR subject:alert OR subject:spent)"

    /// Scans Gmail for payment emails since `sinceDate`, creating draft expenses for parseable
    /// messages and recording every processed message id for dedup. Returns counts of created
    /// and failed expenses. Uses `refreshTokenIfNeeded()` only — never triggers interactive sign-in.
    func sync(
        auth: AuthState,
        modelContext: ModelContext,
        sinceDate: Date,
        progress: ((String) -> Void)? = nil,
        onFailure: ((FailedScanEmail) -> Void)? = nil
    ) async -> (created: Int, failed: Int) {
        let expenseService = ExpenseService(auth: auth)
        let patternService = EmailPatternService(auth: auth)
        let accountService = PaymentAccountService(auth: auth)

        do {
            let token = try await gmailAuth.refreshTokenIfNeeded()
            let patterns = (try? await patternService.getPatterns()) ?? []
            if patterns.isEmpty { return (0, 0) }
            let accounts = (try? await accountService.getAccounts()) ?? []

            progress?("Searching Gmail for payment emails...")
            let messageIds = try await gmailFetch.listMessageIds(accessToken: token, query: syncQuery, sinceDate: sinceDate)

            var created = 0
            var failed = 0

            for (index, msgId) in messageIds.enumerated() {
                if Task.isCancelled { break }
                if isDuplicate(gmailMessageId: msgId, context: modelContext) { continue }
                progress?("Processing \(index + 1) of \(messageIds.count)...")

                do {
                    let message = try await gmailFetch.getMessage(accessToken: token, messageId: msgId)
                    if let parsed = emailParser.parse(message: message, patterns: patterns) {
                        let accountId = parsed.bankName.flatMap { bank in
                            accounts.first { $0.bank?.localizedCaseInsensitiveContains(bank) == true }?.id
                        }
                        let req = CreateExpenseRequest(
                            amount: parsed.amount,
                            merchant: parsed.merchant,
                            paymentMethod: parsed.paymentMethod,
                            transactionDate: parsed.transactionDate,
                            source: .email,
                            status: .draft,
                            rawSmsText: Self.cleanRawText(message.body),
                            paymentAccountId: accountId
                        )
                        do {
                            let expense = try await expenseService.createExpense(req)
                            saveProcessed(gmailMessageId: msgId, serverExpenseId: expense.id, context: modelContext)
                            created += 1
                        } catch {
                            onFailure?(FailedScanEmail(
                                subject: message.subject,
                                parsedAmount: parsed.amount,
                                parsedMerchant: parsed.merchant,
                                strippedBody: message.body,
                                errorMessage: error.localizedDescription
                            ))
                            failed += 1
                        }
                    } else {
                        saveProcessed(gmailMessageId: msgId, serverExpenseId: nil, context: modelContext)
                    }
                } catch {
                    // Skip timed-out or network-failed messages — don't block the whole scan
                    let isTimeout = (error as NSError).code == NSURLErrorTimedOut ||
                                    (error as NSError).code == NSURLErrorNetworkConnectionLost
                    print("⚠️ [SCAN] Skipping message \(msgId): \(error.localizedDescription)")
                    if !isTimeout { failed += 1 }
                }
            }

            UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
            return (created, failed)
        } catch {
            print("⚠️ [SCAN] Sync failed: \(error.localizedDescription)")
            return (0, 0)
        }
    }

    static func cleanRawText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(500).description
    }

    private func isDuplicate(gmailMessageId: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ProcessedGmailMessage>(
            predicate: #Predicate { $0.gmailMessageId == gmailMessageId }
        )
        return (try? context.fetch(descriptor))?.isEmpty == false
    }

    private func saveProcessed(gmailMessageId: String, serverExpenseId: String?, context: ModelContext) {
        let record = ProcessedGmailMessage(gmailMessageId: gmailMessageId, serverExpenseId: serverExpenseId)
        context.insert(record)
        try? context.save()
    }
}
