import Foundation
import Observation
import SwiftData
import UIKit

struct FailedScanEmail: Identifiable {
    let id = UUID()
    let subject: String
    let parsedAmount: Double?
    let parsedMerchant: String?
    let strippedBody: String
    let errorMessage: String
}

enum SyncProgress {
    case idle
    case running(message: String)
    case completed(created: Int, failed: Int)
    case failed(error: String)
}

@Observable
@MainActor
final class MailConnectorViewModel: AuthedViewModel {
    var isSignedIn = false
    var googleEmail: String?
    var syncProgress: SyncProgress = .idle
    var sinceDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var isSyncing = false
    var failedEmails: [FailedScanEmail] = []
    private var syncTask: Task<(created: Int, failed: Int), Never>?

    private let gmailAuth = GmailAuthService.shared
    private let syncEngine = GmailSyncEngine()
    private let auth: AuthState
    private var modelContext: ModelContext?

    private let lastSyncKey = GmailSyncEngine.lastSyncKey

    init(auth: AuthState) {
        self.auth = auth
        gmailAuth.restoreSession()
        refreshSignInState()
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func refreshSignInState() {
        isSignedIn = gmailAuth.isSignedIn
        googleEmail = gmailAuth.userEmail
    }

    func signIn() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let vc = scene.windows.first?.rootViewController else { return }
        do {
            _ = try await gmailAuth.signIn(presenting: vc)
            refreshSignInState()
        } catch {
            syncProgress = .failed(error: error.localizedDescription)
        }
    }

    func signOut() {
        gmailAuth.signOut()
        refreshSignInState()
        syncProgress = .idle
    }

    func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
        syncProgress = .idle
    }

    func startSync() async {
        guard !isSyncing, let modelContext else { return }
        isSyncing = true
        failedEmails = []
        syncProgress = .running(message: "Fetching email patterns...")

        // Run inside a stored, cancellable Task so `cancelSync()` can stop the loop
        // (the engine honors `Task.isCancelled`).
        let task = Task { [auth, syncEngine, sinceDate] () -> (created: Int, failed: Int) in
            await syncEngine.sync(
                auth: auth,
                modelContext: modelContext,
                sinceDate: sinceDate,
                progress: { [weak self] msg in self?.syncProgress = .running(message: msg) },
                onFailure: { [weak self] failed in self?.failedEmails.append(failed) }
            )
        }
        syncTask = task
        let result = await task.value
        syncTask = nil

        if !task.isCancelled {
            syncProgress = .completed(created: result.created, failed: result.failed)
        }
        isSyncing = false
    }

    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    func clearScanHistory() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<ProcessedGmailMessage>()
        if let all = try? context.fetch(descriptor) {
            all.forEach { context.delete($0) }
            try? context.save()
        }
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        syncProgress = .idle
        failedEmails = []
    }
}
