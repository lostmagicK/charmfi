import SwiftUI

/// Lays its children out in a multi-column **masonry** grid on regular width
/// (iPad) and a single column on compact width (iPhone).
///
/// Masonry (each card flows into the currently-shortest column, keeping its
/// natural height) is used instead of `LazyVGrid` so cards of differing heights
/// don't leave ragged gaps — every row in a `LazyVGrid` is forced to the tallest
/// card's height. The compact branch is the exact `LazyVStack` the feature
/// screens already used, so iPhone layout is unchanged.
struct AdaptiveGrid<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    var minColumnWidth: CGFloat = 340
    var spacing: CGFloat = 12
    /// When true, every cell is sized to the tallest card so the grid reads as
    /// uniform rows (good for homogeneous cards). When false (default), cards
    /// keep their natural heights and pack as masonry.
    var uniformHeights: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        if hSize == .regular {
            if uniformHeights {
                UniformGridLayout(minColumnWidth: minColumnWidth, spacing: spacing) {
                    content
                }
            } else {
                MasonryLayout(minColumnWidth: minColumnWidth, spacing: spacing) {
                    content
                }
            }
        } else {
            LazyVStack(spacing: spacing) {
                content
            }
        }
    }
}

/// A row-major grid `Layout` that gives every cell the same height (the tallest
/// card's), so homogeneous cards line up cleanly with no ragged gaps. Cards are
/// proposed the uniform cell height, so a card that fills its frame (e.g. via
/// `.frame(maxHeight: .infinity)`) will stretch to match its row-mates.
struct UniformGridLayout: Layout {
    var minColumnWidth: CGFloat
    var spacing: CGFloat

    private func columnCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + spacing) / (minColumnWidth + spacing)))
    }

    private func columnWidth(for width: CGFloat, columns: Int) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func cellHeight(_ subviews: Subviews, _ colWidth: CGFloat) -> CGFloat {
        subviews.map { $0.sizeThatFits(.init(width: colWidth, height: nil)).height }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? minColumnWidth
        let columns = columnCount(for: width)
        let colWidth = columnWidth(for: width, columns: columns)
        let height = cellHeight(subviews, colWidth)
        let rows = Int(ceil(Double(subviews.count) / Double(columns)))
        let total = CGFloat(rows) * height + CGFloat(max(0, rows - 1)) * spacing
        return CGSize(width: width, height: max(0, total))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let columns = columnCount(for: bounds.width)
        let colWidth = columnWidth(for: bounds.width, columns: columns)
        let height = cellHeight(subviews, colWidth)

        for (i, subview) in subviews.enumerated() {
            let row = i / columns
            let col = i % columns
            let x = bounds.minX + CGFloat(col) * (colWidth + spacing)
            let y = bounds.minY + CGFloat(row) * (height + spacing)
            subview.place(at: CGPoint(x: x, y: y),
                          proposal: .init(width: colWidth, height: height))
        }
    }
}

/// A column-balanced masonry `Layout`: it derives the column count from the
/// available width, then places each subview into the shortest column so cards
/// pack tightly regardless of their individual heights.
struct MasonryLayout: Layout {
    var minColumnWidth: CGFloat
    var spacing: CGFloat

    private func columnCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + spacing) / (minColumnWidth + spacing)))
    }

    private func columnWidth(for width: CGFloat, columns: Int) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? minColumnWidth
        let columns = columnCount(for: width)
        let colWidth = columnWidth(for: width, columns: columns)

        var heights = Array(repeating: CGFloat.zero, count: columns)
        for subview in subviews {
            let h = subview.sizeThatFits(.init(width: colWidth, height: nil)).height
            let idx = shortestColumn(heights)
            heights[idx] += h + spacing
        }
        let tallest = (heights.max() ?? spacing) - spacing
        return CGSize(width: width, height: max(tallest, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let columns = columnCount(for: bounds.width)
        let colWidth = columnWidth(for: bounds.width, columns: columns)

        var heights = Array(repeating: CGFloat.zero, count: columns)
        for subview in subviews {
            let size = subview.sizeThatFits(.init(width: colWidth, height: nil))
            let idx = shortestColumn(heights)
            let x = bounds.minX + CGFloat(idx) * (colWidth + spacing)
            let y = bounds.minY + heights[idx]
            subview.place(at: CGPoint(x: x, y: y),
                          proposal: .init(width: colWidth, height: size.height))
            heights[idx] += size.height + spacing
        }
    }

    private func shortestColumn(_ heights: [CGFloat]) -> Int {
        heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
    }
}

/// Caps content width and centers it on regular width (iPad); no-op on compact
/// width (iPhone). Used for Form/List settings screens where a grid of fields
/// would make no sense but edge-to-edge stretching looks poor on iPad.
private struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if hSize == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// On iPad, constrains the view to `maxWidth` and centers it horizontally.
    /// On iPhone this does nothing.
    func adaptiveReadableWidth(_ maxWidth: CGFloat = 700) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}
