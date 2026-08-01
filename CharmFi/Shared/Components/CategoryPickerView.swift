import SwiftUI

struct CategoryPickerView: View {
    @Binding var selectedCategoryId: String?
    let categories: [Category]

    @State private var l1Id: String?
    @State private var l2Id: String?
    @State private var l3Id: String?
    @State private var l4Id: String?

    private var l1Categories: [Category] { categories }
    private var l2Categories: [Category] { l1Id.flatMap { id in categories.first(where: { $0.id == id }) }?.children ?? [] }
    private var l3Categories: [Category] { l2Id.flatMap { id in l2Categories.first(where: { $0.id == id }) }?.children ?? [] }
    private var l4Categories: [Category] { l3Id.flatMap { id in l3Categories.first(where: { $0.id == id }) }?.children ?? [] }

    var body: some View {
        Group {
            picker("Category", items: l1Categories, selection: $l1Id)
                .onChange(of: l1Id) { l2Id = nil; l3Id = nil; l4Id = nil; updateSelection() }

            if !l2Categories.isEmpty {
                picker("Subcategory", items: l2Categories, selection: $l2Id)
                    .onChange(of: l2Id) { l3Id = nil; l4Id = nil; updateSelection() }
            }

            if !l3Categories.isEmpty {
                picker("Level 3", items: l3Categories, selection: $l3Id)
                    .onChange(of: l3Id) { l4Id = nil; updateSelection() }
            }

            if !l4Categories.isEmpty {
                picker("Level 4", items: l4Categories, selection: $l4Id)
                    .onChange(of: l4Id) { updateSelection() }
            }
        }
        .onAppear { resolveSelection() }
        .onChange(of: selectedCategoryId) { resolveSelection() }
    }

    private func picker(_ label: String, items: [Category], selection: Binding<String?>) -> some View {
        Picker(label, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(items) { cat in
                HStack {
                    if let icon = cat.icon { Text(icon) }
                    Text(cat.name)
                }
                .tag(Optional(cat.id))
            }
        }
    }

    private func updateSelection() {
        selectedCategoryId = l4Id ?? l3Id ?? l2Id ?? l1Id
    }

    private func resolveSelection() {
        guard let id = selectedCategoryId else { l1Id = nil; l2Id = nil; l3Id = nil; l4Id = nil; return }
        let all = categories.flatMap { $0.flatten() }
        guard let target = all.first(where: { $0.id == id }) else { return }
        if let p3 = target.parentId, let l3cat = all.first(where: { $0.id == p3 }) {
            if let p2 = l3cat.parentId, let l2cat = all.first(where: { $0.id == p2 }) {
                if let p1 = l2cat.parentId {
                    l1Id = p1; l2Id = p2; l3Id = p3; l4Id = id
                } else {
                    l1Id = p2; l2Id = p3; l3Id = id; l4Id = nil
                }
            } else {
                l1Id = p3; l2Id = id; l3Id = nil; l4Id = nil
            }
        } else if let parentId = target.parentId {
            l1Id = parentId; l2Id = id; l3Id = nil; l4Id = nil
        } else {
            l1Id = id; l2Id = nil; l3Id = nil; l4Id = nil
        }
    }
}
