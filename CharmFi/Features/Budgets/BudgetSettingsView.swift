import SwiftUI

/// Opts category subtrees out of monthly budget planning (transfers, card payments, anything
/// that isn't really "spend"). Mirrors Android's `BudgetSettingsScreen`. Ticking a bucket covers
/// its whole subtree — descendants show checked-but-disabled with an "inherited" label — and only
/// explicit ids are stored, stripped of any now-redundant descendant ids on toggle.
struct BudgetSettingsView: View {
    @Environment(AuthState.self) private var authState
    @State private var categories: [Category] = []
    @State private var excluded: Set<String> = []
    @State private var saved: Set<String> = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?

    private var budgetService: BudgetService { BudgetService(auth: authState) }
    private var categoryService: CategoryService { CategoryService(auth: authState) }

    // Trip buckets are always out of monthly planning already — no point offering them here.
    private var roots: [Category] { categories.filter { !($0.name == "Trip" && $0.isGlobal) } }
    private var isDirty: Bool { excluded != saved }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let error {
                            ErrorBannerView(message: error) { self.error = nil }
                        }
                        explainer
                        ForEach(roots) { root in
                            ExclusionRootCard(category: root, excluded: $excluded)
                        }
                        Spacer().frame(height: 80)
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Budget Settings")
        .adaptiveReadableWidth()
        .toolbar {
            if isDirty {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Discard") { excluded = saved }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isDirty {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Save changes").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
                .padding()
                .background(.regularMaterial)
            }
        }
        .task { await load() }
    }

    private var explainer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text("Excluded categories — transfers, credit-card payments and similar — are left out of budgets, dashboard totals and AI analysis. \(excluded.count) excluded.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        isLoading = true
        error = nil
        async let cats = categoryService.getCategories()
        async let exc = budgetService.getExcludedCategories()
        do {
            let (c, e) = try await (cats, exc)
            categories = c
            excluded = Set(e)
            saved = Set(e)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        do {
            try await budgetService.setExcludedCategories(Array(excluded))
            saved = excluded
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

/// Ticking a category excludes its whole subtree — any descendant id already in the set becomes
/// redundant, so it's stripped rather than left to linger.
private func togglingExclusion(_ cat: Category, in set: Set<String>) -> Set<String> {
    var s = set
    if s.contains(cat.id) {
        s.remove(cat.id)
    } else {
        s.insert(cat.id)
        func strip(_ c: Category) {
            for child in c.children { s.remove(child.id); strip(child) }
        }
        strip(cat)
    }
    return s
}

private func countExcluded(_ cat: Category, _ excluded: Set<String>) -> Int {
    var n = excluded.contains(cat.id) ? 1 : 0
    for child in cat.children { n += countExcluded(child, excluded) }
    return n
}

private struct ExclusionRootCard: View {
    let category: Category
    @Binding var excluded: Set<String>
    @State private var expanded = false

    private var isExcluded: Bool { excluded.contains(category.id) }
    private var excludedCount: Int { countExcluded(category, excluded) }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    ExclusionCheckbox(isOn: isExcluded, disabled: false) {
                        excluded = togglingExclusion(category, in: excluded)
                    }
                    if let icon = category.icon, !icon.isEmpty { Text(icon) }
                    Text(category.name)
                        .font(.subheadline.bold())
                        .strikethrough(isExcluded)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if excludedCount > 0 {
                        Text("\(excludedCount) excluded").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !category.children.isEmpty {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if expanded && !category.children.isEmpty {
                Divider()
                ForEach(category.children) { child in
                    ExclusionChildRow(category: child, depth: 1, ancestorExcluded: isExcluded, excluded: $excluded)
                    Divider().padding(.leading, 32)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ExclusionChildRow: View {
    let category: Category
    let depth: Int
    let ancestorExcluded: Bool
    @Binding var excluded: Set<String>
    @State private var expanded = false

    private var isExcludedDirectly: Bool { excluded.contains(category.id) }
    private var isExcluded: Bool { ancestorExcluded || isExcludedDirectly }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ExclusionCheckbox(isOn: isExcluded, disabled: ancestorExcluded) {
                    excluded = togglingExclusion(category, in: excluded)
                }
                Text(category.name).font(.subheadline).strikethrough(isExcluded)
                if ancestorExcluded {
                    Text("inherited").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if !category.children.isEmpty {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, CGFloat(depth * 16)).padding(.horizontal, 16).padding(.vertical, 8)

            if expanded {
                ForEach(category.children) { child in
                    ExclusionChildRow(category: child, depth: depth + 1, ancestorExcluded: isExcluded, excluded: $excluded)
                }
            }
        }
    }
}

private struct ExclusionCheckbox: View {
    let isOn: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(disabled ? .secondary : (isOn ? Color.accentColor : .secondary))
        }
        .disabled(disabled)
    }
}
