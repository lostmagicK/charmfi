import Foundation

struct ToolOutcome {
    let content: String
    let summary: String
    let isError: Bool

    static func ok(_ value: JSONValue, summary: String) -> ToolOutcome {
        ToolOutcome(content: value.jsonString, summary: summary, isError: false)
    }
    static func error(_ message: String) -> ToolOutcome {
        ToolOutcome(content: JSONValue.object(["error": .string(message)]).jsonString, summary: message, isError: true)
    }
}

/// Executes the tool calls the model makes against the ordinary CharmFI endpoints. Read tools run
/// unconfirmed; write tools (`BudgetTools.writeTools`) are gated behind a confirmation card by the
/// caller before `execute` is ever invoked — this type only does the work once approved.
@MainActor
final class BudgetToolExecutor {
    private let budgetService: BudgetService
    private let categoryService: CategoryService
    private let tagService: TagService
    private let incomeService: IncomeService

    /// Mirrors Android's `HEX_COLOR` — the only colour form the app renders.
    private static let hexColor = /#[0-9a-fA-F]{6}/

    init(auth: AuthState) {
        budgetService = BudgetService(auth: auth)
        categoryService = CategoryService(auth: auth)
        tagService = TagService(auth: auth)
        incomeService = IncomeService(auth: auth)
    }

    /// A human-readable sentence for the "Apply this change?" confirmation card.
    ///
    /// Resolves ids to names so the user sees "Food", not a UUID, and says which month is affected —
    /// approving an unattributed write is approving nothing. Every lookup falls back to a generic
    /// label, because a failed fetch must never block a confirmation. Mirrors Android's
    /// `BudgetToolExecutor.describe` (BudgetToolExecutor.kt).
    func describe(_ name: String, _ input: JSONValue) async -> String {
        switch name {
        case BudgetToolName.setBudgetAmount:
            let amount = input["amount"]?.doubleValue ?? 0
            let label = await budgetName(input["budgetId"]?.stringValue)
            return "Set \(label) to \(amount.formattedINR)\(monthSuffix(input))"
        case BudgetToolName.createBudget:
            let n = input["name"]?.stringValue ?? "a new category"
            let amount = input["amount"]?.doubleValue ?? 0
            return "Create a \(amount.formattedINR) monthly budget for \(n)"
        case BudgetToolName.createCategory:
            let label = [input["icon"]?.stringValue, input["name"]?.stringValue ?? "a new category"]
                .compactMap { $0 }.joined(separator: " ")
            if let parent = await categoryName(input["parentCategoryId"]?.stringValue) {
                return "Create a new category \(label) under \(parent)"
            }
            return "Create a new top-level category \(label)"
        case BudgetToolName.createTag:
            return "Create a new tag \"\(input["name"]?.stringValue ?? "untitled")\""
        case BudgetToolName.addTagToCategory:
            let tag = await tagName(input["tagId"]?.stringValue)
            let category = await categoryName(input["categoryId"]?.stringValue) ?? "this category"
            return "Tag \(category) with \"\(tag)\" — also applies to everything nested under it"
        default:
            return "Apply this change"
        }
    }

    private func budgetName(_ id: String?) async -> String {
        guard let id, let budgets = try? await budgetService.getBudgets(),
              let found = findBudget(id, in: budgets) else { return "this budget" }
        return found.categoryName ?? found.name
    }

    private func tagName(_ id: String?) async -> String {
        guard let id, let tags = try? await tagService.getTags(),
              let found = tags.first(where: { $0.id == id }) else { return "this tag" }
        return found.name
    }

    private func categoryName(_ id: String?) async -> String? {
        guard let id, let categories = try? await categoryService.getCategories() else { return nil }
        return categories.flatMap { $0.flatten() }.first { $0.id == id }?.name
    }

    private func monthSuffix(_ input: JSONValue) -> String {
        guard let year = input["year"]?.intValue, let month = input["month"]?.intValue,
              let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))
        else { return " every month" }
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return " for \(f.string(from: date))"
    }

    func execute(_ name: String, _ input: JSONValue) async -> ToolOutcome {
        do {
            switch name {
            case BudgetToolName.listBudgets: return try await listBudgets(input)
            case BudgetToolName.listTripBudgets: return try await listTripBudgets()
            case BudgetToolName.listCategories: return try await listCategories()
            case BudgetToolName.getCategorySpending: return try await getCategorySpending(input)
            case BudgetToolName.listTags: return try await listTags()
            case BudgetToolName.listIncome: return try await listIncome(input)
            case BudgetToolName.setBudgetAmount: return try await setBudgetAmount(input)
            case BudgetToolName.createBudget: return try await createBudget(input)
            case BudgetToolName.createCategory: return try await createCategory(input)
            case BudgetToolName.createTag: return try await createTag(input)
            case BudgetToolName.addTagToCategory: return try await addTagToCategory(input)
            default: return .error("Unknown tool \(name)")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: Reads

    private func listBudgets(_ input: JSONValue) async throws -> ToolOutcome {
        let budgets = try await budgetService.getBudgets(year: input["year"]?.intValue, month: input["month"]?.intValue)
        var flat: [JSONValue] = []
        func walk(_ b: Budget, parentId: String?) {
            var row: [String: JSONValue] = [
                "id": .string(b.id),
                "name": .string(b.name),
                "categoryId": b.categoryId.map(JSONValue.string) ?? .null,
                "categoryName": b.categoryName.map(JSONValue.string) ?? .null,
                "parentBudgetId": parentId.map(JSONValue.string) ?? .null,
                "amountThisMonth": .number(b.effectiveAmount),
                "defaultAmount": .number(b.defaultAmount),
                "spent": .number(b.spent),
                "remaining": .number(b.remaining),
                // Authoritative per-budget lock: a month that has ended is read-only, and rows can
                // have different cycle start days, so this must come from the server, not a guess.
                "editable": .bool(b.isEditable),
                "hasMonthOverride": .bool(b.isOverridden)
            ]
            if b.isBeforeStart { row["notSetForThisMonth"] = .bool(true) }
            flat.append(.object(row))
            for child in b.children { walk(child, parentId: b.id) }
        }
        for b in budgets { walk(b, parentId: nil) }
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let result = JSONValue.object([
            "year": .number(Double(input["year"]?.intValue ?? now.year ?? 0)),
            "month": .number(Double(input["month"]?.intValue ?? now.month ?? 0)),
            "budgets": .array(flat)
        ])
        return .ok(result, summary: "Listed \(flat.count) budgets")
    }

    private func listTripBudgets() async throws -> ToolOutcome {
        let trips = try await budgetService.getTripBudgets()
        var flat: [JSONValue] = []
        // Recursive: a trip's sub-budgets share its date range and are budgeted in their own right,
        // so the model has to see them too.
        func walk(_ b: Budget, parentId: String?) {
            flat.append(.object([
                "id": .string(b.id),
                "name": .string(b.name),
                "categoryId": b.categoryId.map(JSONValue.string) ?? .null,
                "categoryName": b.categoryName.map(JSONValue.string) ?? .null,
                "parentBudgetId": parentId.map(JSONValue.string) ?? .null,
                "startDate": b.startDate.map { .string($0.apiDateString) } ?? .null,
                "endDate": b.endDate.map { .string($0.apiDateString) } ?? .null,
                "amount": .number(b.defaultAmount),
                "spent": .number(b.spent),
                "remaining": .number(b.remaining)
            ]))
            for child in b.children { walk(child, parentId: b.id) }
        }
        for b in trips { walk(b, parentId: nil) }
        return .ok(.array(flat), summary: "Listed \(flat.count) trip budgets")
    }

    private func listCategories() async throws -> ToolOutcome {
        let all = try await categoryService.getCategories()
        let savingsIds = all.savingsCategoryIds()
        func walk(_ c: Category) -> JSONValue? {
            if c.excludeFromExpenses && !savingsIds.contains(c.id) { return nil }
            return .object([
                "id": .string(c.id),
                "name": .string(c.name),
                "parentId": c.parentId.map(JSONValue.string) ?? .null,
                "savings": .bool(savingsIds.contains(c.id)),
                "children": .array(c.children.compactMap(walk))
            ])
        }
        let items = all.compactMap(walk)
        return .ok(.array(items), summary: "Listed categories")
    }

    private func getCategorySpending(_ input: JSONValue) async throws -> ToolOutcome {
        let spending = try await budgetService.getCategorySpending(year: input["year"]?.intValue, month: input["month"]?.intValue)
        var obj: [String: JSONValue] = [:]
        for (k, v) in spending { obj[k] = .number(v) }
        return .ok(.object(obj), summary: "Fetched category spending")
    }

    private func listTags() async throws -> ToolOutcome {
        let tags = try await tagService.getTags()
        let items: [JSONValue] = tags.map {
            .object(["id": .string($0.id), "name": .string($0.name), "color": .string($0.color)])
        }
        return .ok(.array(items), summary: "Listed \(items.count) tags")
    }

    private func listIncome(_ input: JSONValue) async throws -> ToolOutcome {
        let month = try await incomeService.getMonth(year: input["year"]?.intValue, month: input["month"]?.intValue)
        let bySource: [JSONValue] = month.bySource.map {
            .object(["name": .string($0.name), "kind": .string($0.kind.rawValue), "amount": .number($0.amount)])
        }
        let obj = JSONValue.object([
            "fixedTotal": .number(month.fixedTotal),
            "variableTotal": .number(month.variableTotal),
            "total": .number(month.total),
            "bySource": .array(bySource)
        ])
        return .ok(obj, summary: "Fetched income for \(month.month)/\(month.year)")
    }

    // MARK: Writes

    private func setBudgetAmount(_ input: JSONValue) async throws -> ToolOutcome {
        guard let budgetId = input["budgetId"]?.stringValue, let amount = input["amount"]?.doubleValue else {
            return .error("budgetId and amount are required")
        }
        if let year = input["year"]?.intValue, let month = input["month"]?.intValue {
            try await budgetService.upsertCycle(budgetId: budgetId, year: year, month: month, amount: amount)
        } else {
            let budgets = try await budgetService.getBudgets()
            guard let existing = findBudget(budgetId, in: budgets) else { return .error("Budget \(budgetId) not found") }
            let req = BudgetRequest(
                name: existing.name, defaultAmount: amount, categoryId: existing.categoryId,
                parentBudgetId: existing.parentBudgetId, isMonthly: existing.isMonthly,
                cycleStartDay: existing.cycleStartDay, startDate: existing.startDate, endDate: existing.endDate
            )
            try await budgetService.updateBudget(id: budgetId, req: req)
        }
        return .ok(.object(["ok": .bool(true)]), summary: "Set budget amount to \(amount.formattedINR)")
    }

    private func createBudget(_ input: JSONValue) async throws -> ToolOutcome {
        guard let name = input["name"]?.stringValue else { return .error("name is required") }
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let req = BudgetRequest(
            name: name, defaultAmount: input["amount"]?.doubleValue ?? 0,
            categoryId: input["categoryId"]?.stringValue,
            cycleStartDay: input["cycleStartDay"]?.intValue ?? 1,
            // Pin the first cycle to the current month; the server rejects past months.
            effectiveYear: now.year, effectiveMonth: now.month
        )
        let createdId = try await budgetService.createBudget(req)
        return .ok(.object(["id": .string(createdId)]), summary: "Created budget \"\(name)\"")
    }

    private func createCategory(_ input: JSONValue) async throws -> ToolOutcome {
        guard let name = input["name"]?.stringValue else { return .error("name is required") }
        let parentId = input["parentCategoryId"]?.stringValue
        // The whole tree, not the pruned one — a duplicate of a hidden "not an expense" category
        // is still a duplicate, and the parent has to be resolvable even if it isn't shown.
        let existing = try await categoryService.getCategories()

        var parent: Category?
        if let parentId {
            parent = existing.flatMap { $0.flatten() }.first { $0.id == parentId }
            guard parent != nil else {
                return .error("No category with id \(parentId). Call \(BudgetToolName.listCategories) for valid ids.")
            }
        }

        // Siblings only, matching Android. Names aren't unique app-wide — the backend has no such
        // constraint — so checking the flattened tree rejected legitimate creates like a "Personal
        // Loan" under Debt Servicing when an unrelated one already sat under Personal.
        let siblings = parent?.children ?? existing
        if let clash = siblings.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            // Hand back the id: reuse beats a near-duplicate, since two categories with the same
            // name under one parent split the history and make every later report ambiguous.
            return ToolOutcome(
                content: JSONValue.object([
                    "ok": .bool(false),
                    "reason": .string("A category named \"\(clash.name)\" already exists here."),
                    "existingCategoryId": .string(clash.id)
                ]).jsonString,
                summary: "\"\(clash.name)\" already exists",
                isError: true
            )
        }

        let req = CategoryRequest(
            name: name, icon: input["icon"]?.stringValue,
            // A malformed colour is cosmetic — drop it rather than fail the whole creation.
            color: input["color"]?.stringValue.flatMap { (try? Self.hexColor.wholeMatch(in: $0)) == nil ? nil : $0 },
            parentId: parentId
        )
        let createdId = try await categoryService.createCategory(req)
        return .ok(.object(["id": .string(createdId)]), summary: "Created category \"\(name)\"")
    }

    private func createTag(_ input: JSONValue) async throws -> ToolOutcome {
        guard let name = input["name"]?.stringValue else { return .error("name is required") }
        let existing = try await tagService.getTags()
        if let dup = existing.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return .error("A tag named \"\(name)\" already exists (id \(dup.id))")
        }
        let color = input["color"]?.stringValue ?? "#64748b"
        let created = try await tagService.createTag(TagRequest(name: name, color: color, sortOrder: nil))
        return .ok(.object(["id": .string(created.id)]), summary: "Created tag \"\(name)\"")
    }

    private func addTagToCategory(_ input: JSONValue) async throws -> ToolOutcome {
        guard let categoryId = input["categoryId"]?.stringValue, let tagId = input["tagId"]?.stringValue else {
            return .error("categoryId and tagId are required")
        }
        let categories = try await categoryService.getCategories()
        guard let category = categories.flatMap({ $0.flatten() }).first(where: { $0.id == categoryId }) else {
            return .error("Category \(categoryId) not found")
        }
        // Whole-set replace — re-send the category's existing (unlocked) tags plus the new one.
        var ids = Set(category.ownTagIds())
        ids.insert(tagId)
        try await categoryService.setTags(id: categoryId, tagIds: Array(ids))
        return .ok(.object(["ok": .bool(true)]), summary: "Tagged \"\(category.name)\"")
    }

    private func findBudget(_ id: String, in budgets: [Budget]) -> Budget? {
        for b in budgets {
            if b.id == id { return b }
            if let found = findBudget(id, in: b.children) { return found }
        }
        return nil
    }
}
