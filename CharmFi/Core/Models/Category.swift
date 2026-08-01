import Foundation

struct Category: Codable, Identifiable {
    let id: String
    let name: String
    var icon: String?
    var color: String?
    var parentId: String?
    let isGlobal: Bool
    let isOwn: Bool
    var sortOrder: Int?
    /// Flagged as money movement, not spending (transfers, credit-card payments) — this subtree is
    /// left out of dashboard totals, budgets and AI analysis. Mirrors Android's
    /// `Category.excludeFromExpenses` (domain/model/Expense.kt).
    var excludeFromExpenses: Bool = false
    /// Tags attached directly to this category. Locked ones were pinned by an admin.
    var tags: [TagRef] = []
    /// Read-only tags inherited from this category's ancestors.
    var inheritedTags: [TagRef] = []
    var children: [Category] = []

    init(id: String, name: String, icon: String? = nil, color: String? = nil,
         parentId: String? = nil, isGlobal: Bool = false, isOwn: Bool = true,
         sortOrder: Int? = nil, excludeFromExpenses: Bool = false,
         tags: [TagRef] = [], inheritedTags: [TagRef] = [], children: [Category] = []) {
        self.id = id; self.name = name; self.icon = icon; self.color = color
        self.parentId = parentId; self.isGlobal = isGlobal; self.isOwn = isOwn
        self.sortOrder = sortOrder; self.excludeFromExpenses = excludeFromExpenses
        self.tags = tags; self.inheritedTags = inheritedTags
        self.children = children
    }
}

extension Category {
    func flatten() -> [Category] {
        var result = [self]
        for child in children { result += child.flatten() }
        return result
    }

    /// Tag ids on this category that the current user may change — admin-pinned (locked) ones are
    /// excluded, since the whole-set replace endpoint only ever touches the user's own attachments.
    func ownTagIds() -> [String] {
        tags.filter { !$0.isLocked }.map(\.id)
    }
}

// MARK: - Excluded & savings categories
//
// Mirrors android/app/src/main/java/com/charmfi/app/domain/model/Expense.kt and
// SavingsCategories.kt. Every dashboard/budget figure must be computed against
// `excludedCategoryIds() + savingsCategoryIds()` removed from the expense set, or transfers,
// card payments and savings contributions double- or over-count as ordinary spend.

/// A category named "Savings and Investments" holds money that left the account but was never
/// spent — it moved into a savings/investment vehicle. Matching is by name, not the flag: a
/// personal bucket a user creates under Personal is a savings bucket too, even though only the
/// seeded global root carries `excludeFromExpenses`.
let savingsCategoryName = "Savings and Investments"

extension Collection where Element == Category {
    /// Ids of every category flagged `excludeFromExpenses`, plus everything nested under it.
    /// Expenses booked to these are transfers or card payments rather than spending.
    func excludedCategoryIds() -> Set<String> {
        var ids = Set<String>()
        func collect(_ cat: Category) {
            ids.insert(cat.id)
            cat.children.forEach(collect)
        }
        func walk(_ cat: Category) {
            if cat.excludeFromExpenses { collect(cat) } else { cat.children.forEach(walk) }
        }
        forEach(walk)
        return ids
    }

    /// Every savings bucket, found anywhere in the tree, plus its whole subtree.
    func savingsCategoryIds() -> Set<String> {
        var ids = Set<String>()
        func collect(_ cat: Category) {
            ids.insert(cat.id)
            cat.children.forEach(collect)
        }
        func walk(_ cat: Category) {
            if cat.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(savingsCategoryName) == .orderedSame {
                collect(cat)
            } else {
                cat.children.forEach(walk)
            }
        }
        forEach(walk)
        return ids
    }

    /// The same tree with excluded subtrees removed, for anything that renders categories as spend.
    func pruneExcluded() -> [Category] {
        compactMap { cat -> Category? in
            if cat.excludeFromExpenses { return nil }
            var copy = cat
            copy.children = cat.children.pruneExcluded()
            return copy
        }
    }
}

/// One stacked series on the savings chart: a top-level bucket under "Savings and Investments".
struct SavingsGroup {
    let name: String
    let icon: String?
    let color: String
    /// The group category plus its whole subtree — an expense belongs here if its category is in this set.
    let ids: Set<String>
}

/// Mirrors the web dashboard's palette (frontend/src/app/core/models/savings-categories.ts) — used
/// only when a group category carries no colour of its own.
let savingsGroupColors = ["#0284c7", "#16a34a", "#9333ea", "#d97706", "#6366f1", "#ea580c"]
/// Anything booked straight on a savings root, or past the token ceiling, lands in "Other".
let savingsOtherColor = "#94a3b8"
/// Past this many groups the tail folds into "Other" — more hues stop being distinguishable.
private let maxSavingsGroups = 8

extension Collection where Element == Category {
    /// The top-level buckets under "Savings and Investments" — "Equity", "Debt", "Retirement" and
    /// so on — each carrying the ids of its whole subtree. Groups of the same name under different
    /// savings roots merge into a single series.
    func savingsGroups() -> [SavingsGroup] {
        struct Builder { let name: String; let icon: String?; let color: String; var ids: Set<String> = [] }

        var byName: [String: Builder] = [:]
        var order: [String] = []
        func subtree(_ cat: Category, into ids: inout Set<String>) {
            ids.insert(cat.id)
            for child in cat.children { subtree(child, into: &ids) }
        }
        func addGroup(_ cat: Category) {
            let key = cat.name.trimmingCharacters(in: .whitespaces).lowercased()
            if byName[key] == nil {
                let color = (cat.color?.isEmpty == false ? cat.color! : savingsGroupColors[order.count % savingsGroupColors.count])
                byName[key] = Builder(name: cat.name.trimmingCharacters(in: .whitespaces), icon: cat.icon, color: color)
                order.append(key)
            }
            var ids = byName[key]!.ids
            subtree(cat, into: &ids)
            byName[key]!.ids = ids
        }
        func walk(_ cat: Category) {
            if cat.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(savingsCategoryName) == .orderedSame {
                cat.children.forEach(addGroup)
            } else {
                cat.children.forEach(walk)
            }
        }
        forEach(walk)
        return order.prefix(maxSavingsGroups).map { key in
            let b = byName[key]!
            return SavingsGroup(name: b.name, icon: b.icon, color: b.color, ids: b.ids)
        }
    }
}

struct CategoryRequest: Encodable {
    var name: String
    var icon: String?
    var color: String?
    var parentId: String?
}

struct ReorderItem: Encodable {
    var id: String
    var sortOrder: Int
}
