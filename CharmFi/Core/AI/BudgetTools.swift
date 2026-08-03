import Foundation

/// The agentic tool set offered to the insights chat. Mirrors Android's `BudgetTools.kt` — same
/// names, same parameter schemas, same write/read split — so the system prompt and the backend's own
/// validation messages stay meaningful regardless of which client produced the call.
///
/// Descriptions state *when* to call the tool, not just what it does: models reach for tools
/// conservatively, and a prescriptive trigger condition measurably improves the should-call rate.
/// They also carry the rules the server enforces (past months are locked, a parent must cover its
/// children) so the model can avoid a rejection rather than discover it. Writes are gated behind a
/// user confirmation, which the descriptions say, so the model narrates a change rather than
/// announcing it as already done.
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
               description: """
                   List the user's monthly budgets for one month, with each budget's id, category, \
                   amount for that month, amount spent, and whether that month can still be edited. \
                   Call this before answering any question about budget amounts or headroom, and \
                   always before changing an amount — never guess a budgetId. \
                   This never includes trip/event budgets — those have a fixed date range instead of \
                   a monthly cycle. Call list_trip_budgets for those instead.
                   """,
               parameters: .schema([
                   ("year", .prop("integer", "Calendar year, e.g. 2026. Defaults to the current month.")),
                   ("month", .prop("integer", "Month number 1-12. Defaults to the current month.")),
               ])),
        AiTool(name: BudgetToolName.listTripBudgets,
               description: """
                   List the user's trip/event budgets — one-off budgets with a fixed date range (e.g. \
                   a vacation or a wedding) instead of a recurring monthly cycle, usually nested under \
                   a "Trips and Events" category. Each entry has its id, category, date range, total \
                   budgeted amount, and amount spent so far within that range. \
                   Call this whenever the user asks about a trip, vacation, or event by name, or about \
                   spending outside their normal monthly budgets — list_budgets does not include these.
                   """,
               parameters: .schema([])),
        AiTool(name: BudgetToolName.listCategories,
               description: """
                   List the user's expense categories as a tree with their ids and names. Call this \
                   when you need a categoryId to create a budget, or to check whether a category the \
                   user named actually exists. \
                   A category marked "savings": true (e.g. Savings and Investments) holds money moved \
                   into savings or investments, not spend — it is left out of every spend total shown \
                   elsewhere, but is still a normal, budgetable category: treat "budget my savings" or \
                   "set a savings goal" as a regular budget on it, not as an expense limit.
                   """,
               parameters: .schema([])),
        AiTool(name: BudgetToolName.getCategorySpending,
               description: """
                   Get actual amount booked per category id for one month, including categories that \
                   have no budget. Call this when the user asks where money went, or when you need a \
                   real figure to recommend an amount. \
                   The amount under a category flagged "savings": true in list_categories is money \
                   saved, not spent — report and reason about it separately from spend.
                   """,
               parameters: .schema([
                   ("year", .prop("integer", "Calendar year, e.g. 2026. Defaults to the current month.")),
                   ("month", .prop("integer", "Month number 1-12. Defaults to the current month.")),
               ])),
        AiTool(name: BudgetToolName.setBudgetAmount,
               description: """
                   Change the amount of an existing budget. Requires the user's approval before it \
                   runs, so state the change in one sentence first. \
                   Give year and month to set the amount for that single month only, leaving other \
                   months alone — this is what the user usually means. Omit both to change the \
                   budget's recurring default amount for every month that has no explicit override. \
                   Past months cannot be changed. A parent category's budget must be at least the sum \
                   of its children's, and a child's cannot push the siblings' total past the parent's.
                   """,
               parameters: .schema([
                   ("budgetId", .prop("string", "The budget's id, from list_budgets.")),
                   ("amount", .prop("number", "The new amount in the user's currency.")),
                   ("year", .prop("integer", "Calendar year of the single month to change.")),
                   ("month", .prop("integer", "Month number 1-12 of the single month to change.")),
               ], required: ["budgetId", "amount"])),
        AiTool(name: BudgetToolName.createBudget,
               description: """
                   Create a new monthly budget for a category that has none yet. Requires the user's \
                   approval before it runs, so state what you are creating first. \
                   Check list_budgets first — if a budget for the category already exists, use \
                   set_budget_amount instead. Omit categoryId only for the overall all-spending budget.
                   """,
               parameters: .schema([
                   ("name", .prop("string", "Display name, usually the category name.")),
                   ("amount", .prop("number", "The monthly amount in the user's currency.")),
                   ("categoryId", .prop("string", "Category this budget covers, from list_categories. Omit for the overall budget.")),
                   ("cycleStartDay", .prop("integer", "Day of month the budget cycle starts, 1-28. Defaults to 1. Only set this if the user's pay cycle does not start on the 1st.")),
               ])),
        AiTool(name: BudgetToolName.createCategory,
               description: """
                   Create a new expense category. Requires the user's approval before it runs, so say \
                   what you are creating first. \
                   Call list_categories first — if a category with that meaning already exists, use it \
                   rather than creating a near-duplicate. Use this when the user wants to track \
                   something that has no category yet, or before creating a budget for a category that \
                   does not exist. Creating a category does not create a budget for it; call \
                   create_budget afterwards if the user asked for a budget too.
                   """,
               parameters: .schema([
                   ("name", .prop("string", "The category name, e.g. \"Coffee\".")),
                   ("parentCategoryId", .prop("string", "Nest under this existing category, from list_categories. Omit for a new top-level category. Prefer nesting when the new category is a kind of an existing one — e.g. Coffee under Food.")),
                   ("icon", .prop("string", "A single emoji representing the category, e.g. \"☕\".")),
                   ("color", .prop("string", "A 6-digit hex colour fitting the category, e.g. \"#8b5cf6\".")),
               ], required: ["name"])),
        AiTool(name: BudgetToolName.listTags,
               description: """
                   List the user's tags with their ids, names and colours. Tags are labels that cut \
                   across the category tree — a transaction can carry several, and a category passes \
                   its tags down to every category and transaction beneath it. \
                   Call this before creating a tag, to reuse an existing one instead of making a \
                   near-duplicate, and before add_tag_to_category — never guess a tagId.
                   """,
               parameters: .schema([])),
        AiTool(name: BudgetToolName.createTag,
               description: """
                   Create a new tag. Requires the user's approval before it runs, so say what you are \
                   creating first. \
                   Call list_tags first and reuse an existing tag if one already means the same thing. \
                   Creating a tag does not attach it to anything; call add_tag_to_category afterwards \
                   to apply it. Use a tag rather than a category when the label cuts across categories \
                   — e.g. "Reimbursable" or "Work trip", which can apply to food, travel and more.
                   """,
               parameters: .schema([
                   ("name", .prop("string", "The tag name, e.g. \"Reimbursable\".")),
                   ("color", .prop("string", "A 6-digit hex colour, e.g. \"#8b5cf6\". Defaults to slate.")),
               ], required: ["name"])),
        AiTool(name: BudgetToolName.addTagToCategory,
               description: """
                   Attach an existing tag to a category. Requires the user's approval before it runs, \
                   so state what you are tagging first. \
                   The tag then applies to that category, to every category nested under it, and to \
                   every transaction booked to any of them — so attach at the highest category that \
                   should carry it rather than tagging each child separately. \
                   Get both ids first: tagId from list_tags, categoryId from list_categories. This adds \
                   to the category's existing tags; it does not replace them.
                   """,
               parameters: .schema([
                   ("categoryId", .prop("string", "The category to tag, from list_categories.")),
                   ("tagId", .prop("string", "The tag to attach, from list_tags.")),
               ], required: ["categoryId", "tagId"])),
        AiTool(name: BudgetToolName.listIncome,
               description: """
                   List the user's income sources and this month's (or another month's) amount per \
                   source, split Fixed vs Variable, with the month's total. Call this when the user \
                   asks about income, savings rate, or how spending compares to what they earn — the \
                   context summary already includes the current period's income, so only call this \
                   for a different month or more source detail than the summary shows.
                   """,
               parameters: .schema([
                   ("year", .prop("integer", "Calendar year, e.g. 2026. Defaults to the current month.")),
                   ("month", .prop("integer", "Month number 1-12. Defaults to the current month.")),
               ])),
    ]
}
