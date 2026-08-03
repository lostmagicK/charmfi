import Foundation
import Observation

enum AiPeriod: String, CaseIterable, Identifiable {
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case last3Months = "Last 3 months"
    case thisYear = "This year"

    var id: String { rawValue }

    /// Key saved transcripts are filed under. Deliberately not `rawValue`, which is a display
    /// label — rewording a label would otherwise orphan every conversation saved under it.
    var storageKey: String {
        switch self {
        case .thisMonth: "thisMonth"
        case .lastMonth: "lastMonth"
        case .last3Months: "last3Months"
        case .thisYear: "thisYear"
        }
    }

    func toDashboardPeriod() -> DashboardPeriod {
        let now = DashboardPeriod.current()
        switch self {
        case .thisMonth: return now
        case .lastMonth: return now.prev()
        case .last3Months: return now
        case .thisYear: return now.withMode(.year)
        }
    }
}

struct ToolActivity: Identifiable {
    let id = UUID()
    var name: String
    var summary: String
    var ok: Bool
}

/// One bubble in the transcript. `role == "user"` renders as a right-aligned pill; assistant
/// turns render as markdown and accumulate live while streaming.
struct DisplayMessage: Identifiable {
    let id = UUID()
    var role: String
    var text: String = ""
    var thinking: String = ""
    var toolActivity: [ToolActivity] = []
    var isStreaming: Bool = false
}

struct PendingConfirmation {
    let toolName: String
    let summary: String
    let decide: (Bool) -> Void
}

@Observable
@MainActor
final class AiInsightsViewModel: AuthedViewModel {
    /// Set through `selectPeriod(_:)` — changing it has to swap the transcript with it.
    private(set) var period: AiPeriod = .thisMonth
    var messages: [DisplayMessage] = []
    var isBusy = false
    var error: String?
    var pendingConfirmation: PendingConfirmation?

    static let suggestions = [
        "Where did most of my money go this period?",
        "Am I on track with my budgets?",
        "What's recurring that I could cut?",
        "How does this period compare to the last one?"
    ]

    private let auth: AuthState
    private let contextBuilder: ExpenseContextBuilder
    private let toolExecutor: BudgetToolExecutor
    private let factory = LlmClientFactory.shared
    private var apiHistory: [AiMessage] = []
    private var contextText: String?
    private var runTask: Task<Void, Never>?

    private static let maxToolRounds = 8

    init(auth: AuthState) {
        self.auth = auth
        contextBuilder = ExpenseContextBuilder(auth: auth)
        toolExecutor = BudgetToolExecutor(auth: auth)
        loadHistory()
    }

    /// Switching period switches conversations. Each period's answers are grounded in that
    /// period's expense snapshot, so carrying one thread across all four made the model reason
    /// about last month's numbers while the user was looking at this month's.
    func selectPeriod(_ newPeriod: AiPeriod) {
        guard newPeriod != period else { return }
        // Abandon anything in flight — its reply belongs to the period being left.
        pendingConfirmation?.decide(false)
        runTask?.cancel()
        runTask = nil
        isBusy = false
        period = newPeriod
        contextText = nil
        error = nil
        loadHistory()
    }

    var hasKey: Bool { factory.hasKey(for: .insightsChat) }
    var modelLabel: String { factory.label(for: .insightsChat) }

    /// Full reset, not just a transcript wipe. `ViewModelStore` caches this model for the whole
    /// session, so anything left mid-flight — a stream that never returned, or a confirmation
    /// card that was still up when the page was closed — outlives the view and keeps `isBusy` /
    /// `pendingConfirmation` set, which disables the composer and its send button with no way
    /// back. Trash has to be the way out of that too.
    func clear() {
        // Hand the awaiting turn a "declined" so its continuation isn't stranded.
        pendingConfirmation?.decide(false)
        runTask?.cancel()
        runTask = nil
        isBusy = false
        messages = []
        apiHistory = []
        contextText = nil
        error = nil
        AiChatStore.clear(period: period.storageKey)
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        messages.append(DisplayMessage(role: "user", text: trimmed))
        apiHistory.append(AiMessage(role: "user", text: trimmed))
        runTask = Task { await runLoop(userText: trimmed) }
    }

    private func runLoop(userText: String) async {
        isBusy = true
        error = nil
        // A `defer`, not a trailing assignment: the ordinary finish — an answer with no tool call —
        // returns from inside the loop below, which skipped the reset entirely and left `isBusy`
        // true for the life of the (session-cached) model, disabling the composer for good.
        defer { isBusy = false }

        // The exchange belongs to the period it was asked in, even if the user switches while it
        // streams, so capture it rather than reading `period` back at the end.
        let askedPeriod = period
        let firstReply = messages.count

        do {
            if contextText == nil {
                contextText = await contextBuilder.build(period: period.toDashboardPeriod())
            }
            let client = try factory.client(for: .insightsChat)
            let model = factory.model(for: .insightsChat)
            let system = systemPrompt(context: contextText ?? "")

            for _ in 0..<Self.maxToolRounds {
                let turn = try await streamOneTurn(client: client, model: model, system: system)
                apiHistory.append(AiMessage(role: "assistant", content: turn.blocks))

                let calls = turn.blocks.filter { $0.type == "tool_use" }
                guard turn.stopReason == "tool_use", !calls.isEmpty else {
                    persist(userText: userText, repliesFrom: firstReply, period: askedPeriod)
                    return
                }

                var results: [AiBlock] = []
                for call in calls {
                    results.append(await runCall(call))
                }
                apiHistory.append(AiMessage(role: "user", content: results))
            }
            messages.append(DisplayMessage(role: "assistant",
                text: "\n\nI stopped after \(Self.maxToolRounds) steps to avoid looping. Ask again to continue."))
            persist(userText: userText, repliesFrom: firstReply, period: askedPeriod)
        } catch {
            // A cancel came from `clear()`, which has already reset everything — don't put an
            // error banner back on the screen the user just emptied.
            if !Task.isCancelled {
                let provider = factory.provider(for: .insightsChat)
                self.error = AiErrors.message(for: error, provider: provider)
            }
        }
    }

    /// Writes a finished exchange to the store: the question, then each assistant bubble it
    /// produced. Held until the turn completes rather than saved as it goes, so a request that
    /// fails part-way doesn't leave an unanswered question in the restored transcript.
    ///
    /// Timestamps are nudged apart because several rows written in the same instant would sort
    /// arbitrarily on reload.
    private func persist(userText: String, repliesFrom index: Int, period: AiPeriod) {
        let now = Date()
        AiChatStore.append(period: period.storageKey, role: "user", text: userText, at: now)
        for (offset, message) in messages[index...].enumerated() where !message.text.isEmpty {
            AiChatStore.append(period: period.storageKey, role: message.role, text: message.text,
                               at: now.addingTimeInterval(Double(offset + 1) / 1000))
        }
    }

    /// Replaces the on-screen and API transcripts with whatever is saved for the current period.
    private func loadHistory() {
        let saved = AiChatStore.history(period: period.storageKey)
        messages = saved.map { DisplayMessage(role: $0.role, text: $0.text) }
        apiHistory = saved.map { AiMessage(role: $0.role, text: $0.text) }
    }

    /// Streams one assistant turn into a live-updating bubble, returning once the terminal
    /// `.turn` chunk arrives.
    private func streamOneTurn(client: LlmClient, model: String, system: String) async throws -> (blocks: [AiBlock], stopReason: String?) {
        let index = messages.count
        messages.append(DisplayMessage(role: "assistant", isStreaming: true))

        let request = LlmRequest(model: model, systemPrompt: system, messages: apiHistory,
                                  maxTokens: 16000, thinking: true, tools: BudgetTools.all)
        var result: (blocks: [AiBlock], stopReason: String?) = ([], nil)
        for try await chunk in client.stream(request) {
            switch chunk {
            case .text(let t):
                if messages.indices.contains(index) { messages[index].text += t }
            case .thinking(let t):
                if messages.indices.contains(index) { messages[index].thinking += t }
            case .toolUse:
                break // surfaced via .toolDone once the call actually runs
            case .toolDone(let name, let summary, let ok):
                if messages.indices.contains(index) {
                    messages[index].toolActivity.append(ToolActivity(name: name, summary: summary, ok: ok))
                }
            case .turn(let blocks, let stopReason):
                result = (blocks, stopReason)
            }
        }
        if messages.indices.contains(index) { messages[index].isStreaming = false }
        return result
    }

    private func runCall(_ call: AiBlock) async -> AiBlock {
        let name = call.name ?? ""
        let id = call.id ?? ""
        let input = call.input ?? .emptyObject

        if BudgetTools.writeTools.contains(name) {
            // Resolved before the card goes up: it names the budget/category/tag being changed, so
            // it has to be awaited rather than built inline in the continuation.
            let summary = await toolExecutor.describe(name, input)
            let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                pendingConfirmation = PendingConfirmation(toolName: name, summary: summary) { [weak self] approved in
                    self?.pendingConfirmation = nil
                    continuation.resume(returning: approved)
                }
            }
            if !approved {
                appendToolActivity(name: name, summary: "Change declined", ok: false)
                return .toolResult(toolUseId: id, content: "The user declined this change. Nothing was modified.")
            }
        }

        let outcome = await toolExecutor.execute(name, input)
        appendToolActivity(name: name, summary: outcome.summary, ok: !outcome.isError)
        // A successful write invalidates the grounding snapshot — leaving it cached would have the
        // model keep reasoning against the numbers it just changed.
        if !outcome.isError, BudgetTools.writeTools.contains(name) { contextText = nil }
        return .toolResult(toolUseId: id, content: outcome.content, isError: outcome.isError)
    }

    private func appendToolActivity(name: String, summary: String, ok: Bool) {
        if let last = messages.indices.last {
            messages[last].toolActivity.append(ToolActivity(name: name, summary: summary, ok: ok))
        }
    }

    /// Mirrors Android's `AiRepository.systemPrompt` — the tool-usage block matters as much as the
    /// tool schemas do. Without the domain rules stated here the model guesses at budget semantics
    /// (single-month override vs recurring default), tries to edit locked past months, and announces
    /// changes as done before the confirmation has even been shown.
    private func systemPrompt(context: String) -> String {
        """
        You are CharmFI's spending insights assistant. Today's date is \(Date().apiDateString).
        Resolve relative dates ("next month") against it.

        You have a snapshot of the user's expenses, income and budgets for the selected period below.
        Base every answer on it. For anything not covered — a different time range, a specific
        budget's id, creating or changing something — use the tools instead of guessing.

        Tools: \(BudgetToolName.listBudgets), \(BudgetToolName.listTripBudgets), \(BudgetToolName.listCategories), \
        \(BudgetToolName.getCategorySpending), \(BudgetToolName.listTags), \(BudgetToolName.listIncome) are read-only. \
        \(BudgetToolName.setBudgetAmount), \(BudgetToolName.createBudget), \(BudgetToolName.createCategory), \
        \(BudgetToolName.createTag), \(BudgetToolName.addTagToCategory) change data.

        - Call \(BudgetToolName.listBudgets) before changing an amount — never guess a budgetId.
        - \(BudgetToolName.listBudgets) only covers recurring monthly budgets. For a trip, vacation or
          event budget with a fixed date range, call \(BudgetToolName.listTripBudgets) instead.
        - A monthly budget has a recurring default amount; a per-month override wins for that month
          only. "Set X for August" means a single-month change, not a new default.
        - Past months cannot be edited — respect the `editable` flag on each row. A parent category's
          budget must cover the sum of its children's, so raising a child may require raising the
          parent first.
        - A budget covers a category, so budgeting something new means creating the category first
          and then the budget. Check \(BudgetToolName.listCategories) before creating one — reuse an
          existing category rather than adding a near-duplicate, and nest a specific category under
          the general one it belongs to.
        - Changes need the user's approval before they run, and the app handles asking. State what you
          are about to change in one sentence, then call the tool — don't ask "shall I?" and stop, and
          don't claim a change is done before the tool result comes back.
        - If a tool returns an error, tell the user what the server said and suggest a fix.
        - The summary below already includes this period's income, budget-vs-actual and a trend where
          available. Only call \(BudgetToolName.listIncome) for a different month or more detail.

        Formatting: reply in concise Markdown. Use a `| Category | Amount |`-style table when comparing more than
        three numbers. Use ₹ for amounts. Don't repeat the whole context back verbatim — answer the question.

        Context for \(period.toDashboardPeriod().label):
        \(context)
        """
    }
}
