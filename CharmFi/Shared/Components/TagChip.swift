import SwiftUI

/// Pill using the tag's colour at low-alpha background / full-strength text. Shows a lock glyph —
/// and never a remove control — when the tag is admin-pinned or inherited from a parent category.
/// Mirrors Android's `TagChip`.
struct TagChip: View {
    let tag: TagRef
    var onRemove: (() -> Void)? = nil

    var body: some View {
        let color = Color.fromHex(tag.color)
        HStack(spacing: 3) {
            if tag.isLocked {
                Image(systemName: "lock.fill").font(.system(size: 8))
            }
            Text(tag.name).font(.caption2).lineLimit(1)
            if let onRemove, !tag.isLocked {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.13), in: Capsule())
    }
}
