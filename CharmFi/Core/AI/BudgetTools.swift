import Foundation

/// The agentic tool set offered to the insights chat. Mirrors Android's `BudgetTools.kt` exactly —
/// same names, same parameter schemas, same write/read split — so the system prompt and the
/// backend's own validation messages stay meaningful regardless of which client produced the call.
enum BudgetToolName {
    static let listBudgets = "list_budgets"
    static let listTripBudgets = "list_trip_budgets"
    static let listCategories = "list_categories"
    static let getCategorySpending = "get_category_spending"
    static let setBudgetAmount = "set_budget_amount"
    static let createBudget = "create_budget"
    static let createCategory = "create_category"
    static let listTags = "list_tags"
    static let createTag = "create_tag"
    static let addTagToCategory = "add_tag_to_category"
    static let listIncome = "list_income"
}

enum BudgetTools {
    static let writeTools: Set<String> = [
        BudgetToolName.setBudgetAmount, BudgetToolName.createBudget, BudgetToolName.createCategory,
        BudgetToolName.createTag, BudgetToolName.addTagToCategory
    ]

    static let all: [AiTool] = [
        AiTool(name: BudgetToolName.listBudgets,
               description: "List monthly budgets with id, category, amount, spent and whether they're editable. Excludes trip budgets.",
               parameters: .schema([
                   ("year", .prop("integer", "Calendar year. Defaults to the current month.")),
                   ("month", .prop("integer", "1-12. Defaults to the current month.")),
               ])),
        AiTool(name: BudgetToolName.listTripBudgets,
               description: "List trip/event budgets — id, category, date range, total, spent.",
               parameters: .schema([])),
        AiTool(name: BudgetToolName.listCategories,
               description: "List the category tree with ids and names. Categories flagged as savings hold money moved into savings/investments, not spend.",
               parameters: .schema([])),
        AiTool(name: BudgetToolName.getCategorySpending,
               description: "Actual amount booked per category id for a given month.",
               parameters: .schema([
                   ("year", .prop("integer", "Calendar year. Defaults to the current month.")),
                   ("month", .prop("integer", "1-12. Defaults to the current month.")),
               ])),
        AiTool(name: BudgetToolName.setBudgetAmount,
               description: "Set a budget's amount for a specific month, or its default amount if year/month are omitted. Requires user confirmation.",
               parameters: .schema([
                   ("budgetId", .prop("string", "The budget's id.")),
                   ("amount", .prop("number", "The new amount.")),
                   ("year", .prop("integer", "Calendar year, if setting a specific month's cycle.")),
                   ("month", .prop("integer", "1-12, if setting a specific month's cycle.")),
               ], required: ["budgetId", "amount"])),
        AiTool(name: BudgetToolName.createBudget,
               description: "Create a new budget. Requires user confirmation.",
               parameters: .schema([
                   ("name", .prop("string", "Budget name.")),
                   ("amount", .prop("number", "Default monthly amount.")),
                   ("categoryId", .prop("string", "Category to attach the budget to, if any.")),
                   ("cycleStartDay", .prop("integer", "Day of month the budget cycle starts on. Defaults to 1.")),
               ])),
        AiTool(name: BudgetToolName.createCategory,
               description: "Create a new expense category. Requires user confirmation.",
               parameters: .schema([
                   ("name", .prop("string", "Category name.")),
                   ("parentCategoryId", .prop("string", "Parent category id, if this is a sub-category.")),
                   ("icon", .prop("string", "A single emoji.")),
                   ("color", .prop("string", "Hex color, e.g. #3b82f6.")),
               ], required: ["name"])),
        AiTool(name: BudgetToolName.listTags,
               description: "List tags with id, name and color.",
               parameters: .schema([])),
        AiTool(name: BudgetToolName.createTag,
               description: "Create a new tag. Requires user confirmation.",
               parameters: .schema([
                   ("name", .prop("string", "Tag name.")),
                   ("color", .prop("string", "Hex color, e.g. #64748b.")),
               ], required: ["name"])),
        AiTool(name: BudgetToolName.addTagToCategory,
               description: "Attach an existing tag to a category, so every transaction in that category inherits it. Requires user confirmation.",
               parameters: .schema([
                   ("categoryId", .prop("string", "The category's id.")),
                   ("tagId", .prop("string", "The tag's id.")),
               ], required: ["categoryId", "tagId"])),
        AiTool(name: BudgetToolName.listIncome,
               description: "List recorded income for a month — fixed and variable sources and totals.",
               parameters: .schema([
                   ("year", .prop("integer", "Calendar year. Defaults to the current month.")),
                   ("month", .prop("integer", "1-12. Defaults to the current month.")),
               ])),
    ]
}
