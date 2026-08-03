import Foundation
import SwiftData

/// One persisted line of an AI Insights conversation, so reopening the screen restores what was
/// said. Mirrors Android's `AiChatEntity` / `AiChatDao`.
///
/// Rows are scoped to a period: each period keeps its own transcript, because the model answers
/// against that period's expense snapshot and a reply about last month makes no sense sitting in
/// this month's thread.
///
/// Only plain text turns are stored. Thinking blocks, tool calls and tool results stay in memory
/// for the session — a restored conversation reads back in full, but the model can't replay a
/// half-finished tool exchange from it.
@Model
final class StoredAiChatMessage {
    var period: String
    var role: String
    var text: String
    var createdAt: Date

    init(period: String, role: String, text: String, createdAt: Date = Date()) {
        self.period = period
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

@MainActor
enum AiChatStore {
    /// Saved conversations are kept for 7 days, then pruned on the next load. Matches Android.
    private static let retention: TimeInterval = 7 * 24 * 60 * 60

    private static var context: ModelContext { SwiftDataContainer.shared.mainContext }

    /// The saved conversation for `period`, oldest first, pruning anything past the retention window.
    static func history(period: String) -> [(role: String, text: String)] {
        prune()
        let descriptor = FetchDescriptor<StoredAiChatMessage>(
            predicate: #Predicate { $0.period == period },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.text)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { ($0.role, $0.text) }
    }

    /// Appends one turn. `createdAt` is passed in so a question and the answers to it keep their
    /// order — several rows written in the same instant would otherwise sort arbitrarily.
    static func append(period: String, role: String, text: String, at date: Date = Date()) {
        context.insert(StoredAiChatMessage(period: period, role: role, text: text, createdAt: date))
        try? context.save()
    }

    static func clear(period: String) {
        try? context.delete(model: StoredAiChatMessage.self,
                            where: #Predicate { $0.period == period })
        try? context.save()
    }

    private static func prune() {
        let cutoff = Date(timeIntervalSinceNow: -retention)
        try? context.delete(model: StoredAiChatMessage.self,
                            where: #Predicate { $0.createdAt < cutoff })
    }
}
