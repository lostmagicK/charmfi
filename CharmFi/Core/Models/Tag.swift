import Foundation

/// A tag as it appears attached to a category/expense — the server resolves inheritance at read
/// time, so `inheritedTags` arrives already expanded. Mirrors Android's `TagRef`.
struct TagRef: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let color: String
    var isGlobal: Bool = false
    var isLocked: Bool = false
}

/// A tag as returned/edited from the Tags management screen.
struct TagResponse: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var color: String
    let isGlobal: Bool
    let isOwn: Bool
    let isActive: Bool
    var sortOrder: Int
}

struct TagRequest: Encodable, Sendable {
    var name: String
    var color: String
    var sortOrder: Int?
}

/// Whole-set replace — both the category and expense "set tags" endpoints take the complete
/// desired set of tag ids, not a delta.
struct SetTagsRequest: Encodable, Sendable {
    var tagIds: [String]
}

/// Every tag that applies, own plus inherited, de-duplicated by id with direct tags first.
func effectiveTags(own: [TagRef], inherited: [TagRef]) -> [TagRef] {
    var seen = Set<String>()
    var result: [TagRef] = []
    for t in own + inherited where !seen.contains(t.id) {
        seen.insert(t.id)
        result.append(t)
    }
    return result
}
