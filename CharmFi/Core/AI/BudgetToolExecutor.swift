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

    init(auth: AuthState) {
        budgetService = BudgetService(auth: auth)
        categoryService = CategoryService(auth: auth)
        tagService = TagService(auth: auth)
        incomeService = IncomeService(auth: auth)
    }

    /// A human-readable sentence for the "Apply this change?" confirmation card.
    func describe(_ name: String, _ input: JSONValue) -> String {
        switch name {
        case BudgetToolName.setBudgetAmount:
            let amount = input["amount"]?.doubleValue ?? 0
            return "Set the budget amount to \(amount.formattedINR)?"
        case BudgetToolName.createBudget:
            let n = input["name"]?.stringValue ?? "budget"
            let amount = input["amount"]?.doubleValue ?? 0
            return "Create budget \"\(n)\" at \(amount.formattedINR)/month?"
        case BudgetToolName.createCategory:
            let n = input["name"]?.stringValue ?? "category"
            return "Create category \"\(n)\"?"
        case BudgetToolName.createTag:
            let n = input["name"]?.stringValue ?? "tag"
            return "Create tag \"\(n)\"?"
        case BudgetToolName.addTagToCategory:
            return "Attach this tag to the category?"
        default:
            return "Apply this change?"
        }
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
            flat.append(.object([
                "id": .string(b.id),
                "name": .string(b.name),
                "categoryId": b.categoryId.map(JSONValue.string) ?? .null,
                "categoryName": b.categoryName.map(JSONValue.string) ?? .null,
                "parentBudgetId": parentId.map(JSONValue.string) ?? .null,
                "amount": .number(b.effectiveAmount),
                "spent": .number(b.spent),
                "editable": .bool(true)
            ]))
            for child in b.children { walk(child, parentId: b.id) }
        }
        for b in budgets { walk(b, parentId: nil) }
        return .ok(.array(flat), summary: "Listed \(flat.count) budgets")
    }

    private func listTripBudgets() async throws -> ToolOutcome {
        let trips = try await budgetService.getTripBudgets()
        let items: [JSONValue] = trips.map { b in
            .object([
                "id": .string(b.id),
                "name": .string(b.name),
                "categoryId": b.categoryId.map(JSONValue.string) ?? .null,
                "startDate": b.startDate.map { .string($0.apiDateString) } ?? .null,
                "endDate": b.endDate.map { .string($0.apiDateString) } ?? .null,
                "amount": .number(b.effectiveAmount),
                "spent": .number(b.spent)
            ])
        }
        return .ok(.array(items), summary: "Listed \(items.count) trip budgets")
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
                cycleStartDay: existing.cycleStartDay, startDate: existing.startDate, endDate: existing.endDate,
                rolloverEnabled: existing.rolloverEnabled
            )
            _ = try await budgetService.updateBudget(id: budgetId, req: req)
        }
        return .ok(.object(["ok": .bool(true)]), summary: "Set budget amount to \(amount.formattedINR)")
    }

    private func createBudget(_ input: JSONValue) async throws -> ToolOutcome {
        guard let name = input["name"]?.stringValue else { return .error("name is required") }
        let req = BudgetRequest(
            name: name, defaultAmount: input["amount"]?.doubleValue ?? 0,
            categoryId: input["categoryId"]?.stringValue,
            cycleStartDay: input["cycleStartDay"]?.intValue ?? 1
        )
        let created = try await budgetService.createBudget(req)
        return .ok(.object(["id": .string(created.id)]), summary: "Created budget \"\(name)\"")
    }

    private func createCategory(_ input: JSONValue) async throws -> ToolOutcome {
        guard let name = input["name"]?.stringValue else { return .error("name is required") }
        let existing = try await categoryService.getCategories()
        if existing.flatMap({ $0.flatten() }).contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return .error("A category named \"\(name)\" already exists")
        }
        let req = CategoryRequest(
            name: name, icon: input["icon"]?.stringValue, color: input["color"]?.stringValue,
            parentId: input["parentCategoryId"]?.stringValue
        )
        let created = try await categoryService.createCategory(req)
        return .ok(.object(["id": .string(created.id)]), summary: "Created category \"\(name)\"")
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
