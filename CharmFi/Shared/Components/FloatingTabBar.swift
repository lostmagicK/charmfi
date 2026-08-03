import SwiftUI

extension View {
    /// Hides `TabView`'s own bar. Has to be applied to each tab's *content* — applying it to
    /// the `TabView` itself leaves iPadOS 26's floating top strip on screen.
    @ViewBuilder
    func hidesNativeTabBar(_ hidden: Bool) -> some View {
        if hidden {
            toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }
}

/// Floating pill tab bar used on iPad in place of the native tab bar.
///
/// iPadOS 26 renders `TabView`'s bar as a floating strip pinned to the *top* and offers no
/// supported way to move it, so on regular width the native bar is hidden and this is laid
/// in at the bottom instead. iPhone keeps the stock bottom tab bar.
struct FloatingTabBar: View {
    /// The tab currently showing. `.more` never lands here — it is a button, not a tab.
    let selection: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.bottom, 8)
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(minWidth: 68)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background {
                if isSelected {
                    Capsule().fill(Color.accentColor.opacity(0.14))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
