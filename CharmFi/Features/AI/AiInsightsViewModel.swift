import Foundation
import Observation

enum AiPeriod: String, CaseIterable, Identifiable {
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case last3Months = "Last 3 months"
    case thisYear = "This year"

    var id: String { rawValue }

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
final class AiInsightsViewModel {
    var period: AiPeriod = .thisMonth
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

    private static let maxToolRounds = 8

    init(auth: AuthState) {
        self.auth = auth
        contextBuilder = ExpenseContextBuilder(auth: auth)
        toolExecutor = BudgetToolExecutor(auth: auth)
    }

    var hasKey: Bool { factory.hasKey(for: .insightsChat) }
    var modelLabel: String { factory.label(for: .insightsChat) }

    func clear() {
        messages = []
        apiHistory = []
        contextText = nil
        error = nil
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        messages.append(DisplayMessage(role: "user", text: trimmed))
        apiHistory.append(AiMessage(role: "user", text: trimmed))
        Task { await runLoop() }
    }

    private func runLoop() async {
        isBusy = true
        error = nil
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
                guard turn.stopReason == "tool_use", !calls.isEmpty else { return }

                var results: [AiBlock] = []
                for call in calls {
                    results.append(await runCall(call))
                }
                apiHistory.append(AiMessage(role: "user", content: results))
            }
            messages.append(DisplayMessage(role: "assistant",
                text: "\n\nI stopped after \(Self.maxToolRounds) steps to avoid looping. Ask again to continue."))
        } catch {
            let provider = factory.provider(for: .insightsChat)
            self.error = AiErrors.message(for: error, provider: provider)
        }
        isBusy = false
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
            let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                pendingConfirmation = PendingConfirmation(toolName: name, summary: toolExecutor.describe(name, input)) { [weak self] approved in
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
        return .toolResult(toolUseId: id, content: outcome.content, isError: outcome.isError)
    }

    private func appendToolActivity(name: String, summary: String, ok: Bool) {
        if let last = messages.indices.last {
            messages[last].toolActivity.append(ToolActivity(name: name, summary: summary, ok: ok))
        }
    }

    private func systemPrompt(context: String) -> String {
        """
        You are CharmFI's spending insights assistant. Today's date is \(Date().apiDateString).

        You have a snapshot of the user's expenses, income and budgets for the selected period below.
        For anything not covered in it — a different time range, a specific budget's id, creating or
        changing something — use the tools instead of guessing.

        Tools available: \(BudgetToolName.listBudgets), \(BudgetToolName.listTripBudgets), \(BudgetToolName.listCategories), \
        \(BudgetToolName.getCategorySpending), \(BudgetToolName.listTags), \(BudgetToolName.listIncome) are read-only. \
        \(BudgetToolName.setBudgetAmount), \(BudgetToolName.createBudget), \(BudgetToolName.createCategory), \
        \(BudgetToolName.createTag), \(BudgetToolName.addTagToCategory) change data and always require the user's confirmation \
        before they take effect — call them freely, the app handles asking.

        Formatting: reply in concise Markdown. Use a `| Category | Amount |`-style table when comparing more than
        three numbers. Use ₹ for amounts. Don't repeat the whole context back verbatim — answer the question.

        Context for \(period.toDashboardPeriod().label):
        \(context)
        """
    }
}
