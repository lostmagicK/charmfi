import BackgroundTasks
import Foundation
import SwiftData

/// Drives periodic (~6h) headless Gmail scans via `BGTaskScheduler`, plus a foreground
/// catch-up when the app becomes active after a long gap. Reuses `GmailSyncEngine` so the
/// background scan is identical to the manual Mail Connector scan.
@MainActor
final class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    private init() {}

    /// Must also be listed under `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "in.charmee.charmfi.gmailsync"

    private let syncEngine = GmailSyncEngine()
    private let interval: TimeInterval = 6 * 3600

    /// Set by the app on launch so background runs have an authenticated session + expense API.
    weak var authState: AuthState?

    /// Register the launch handler. Must be called before the app finishes launching.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            // The launch handler runs on a background queue; hop to the main actor. BGTask isn't
            // Sendable, so mark the capture unsafe (consistent with the app's GmailAuthService).
            nonisolated(unsafe) let task = task
            Task { @MainActor in
                BackgroundSyncManager.shared.handle(task: task)
            }
        }
    }

    /// Queue the next background scan ~6h out. A processing task is used (not app-refresh)
    /// because the scan does many network round-trips and can exceed the app-refresh budget.
    func schedule() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("⚠️ [BGSync] Failed to schedule task: \(error.localizedDescription)")
        }
    }

    private func handle(task: BGTask) {
        // Always reschedule the next run first so the cadence continues even if this run bails.
        schedule()

        guard let auth = authState, auth.isAuthenticated, GmailAuthService.shared.isSignedIn else {
            task.setTaskCompleted(success: true)
            return
        }

        let sinceDate = (UserDefaults.standard.object(forKey: GmailSyncEngine.lastSyncKey) as? Date)
            ?? Date(timeIntervalSinceNow: -interval)

        let work = Task { @MainActor in
            let context = SwiftDataContainer.shared.mainContext
            _ = await syncEngine.sync(auth: auth, modelContext: context, sinceDate: sinceDate)
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        task.expirationHandler = { work.cancel() }
    }

    /// Foreground catch-up: if it's been ≥6h (or never synced) and Gmail is connected, scan now.
    func runForegroundCatchUpIfNeeded() async {
        guard let auth = authState, auth.isAuthenticated, GmailAuthService.shared.isSignedIn else { return }

        let last = UserDefaults.standard.object(forKey: GmailSyncEngine.lastSyncKey) as? Date
        let cutoff = Date(timeIntervalSinceNow: -interval)
        guard last == nil || last! < cutoff else { return }

        let sinceDate = last ?? cutoff
        let context = SwiftDataContainer.shared.mainContext
        _ = await syncEngine.sync(auth: auth, modelContext: context, sinceDate: sinceDate)
        schedule()
    }
}
