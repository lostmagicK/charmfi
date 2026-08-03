import SwiftUI

struct CategoriesView: View {
    @Environment(AuthState.self) private var authState
    @State private var categories: [Category] = []
    @State private var allTags: [TagResponse] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showAddRoot = false
    @State private var editingCategory: Category?
    @State private var addingChildOf: Category?
    @State private var taggingCategory: Category?

    private var service: CategoryService { CategoryService(auth: authState) }
    private var tagService: TagService { TagService(auth: authState) }

    var body: some View {
        // The banner sits above the loading/empty/content switch: a failed load leaves `categories`
        // empty, and a banner nested in the populated branch would never render — the failure would
        // read as "No Categories".
        VStack(spacing: 0) {
            if let error {
                ErrorBannerView(message: error) { self.error = nil }.padding(.horizontal, 16)
            }
            if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if categories.isEmpty {
                ContentUnavailableView("No Categories", systemImage: "tag",
                    description: Text("Tap + to add a category"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(categories) { root in
                            AccordionCategoryCard(
                                category: root,
                                depth: 0,
                                onEdit: { editingCategory = $0 },
                                onAddChild: { addingChildOf = $0 },
                                onDelete: { cat in Task { await delete(id: cat.id) } },
                                onEditTags: { taggingCategory = $0 }
                            )
                        }
                        Spacer().frame(height: 80)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Categories")
        .adaptiveReadableWidth()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddRoot = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await load() }
        // Add root
        .sheet(isPresented: $showAddRoot) {
            CategoryDialog(title: "Add Category") { name, icon, color in
                Task { await create(name: name, icon: icon, color: color, parentId: nil) }
            }
        }
        // Add child
        .sheet(item: $addingChildOf) { parent in
            CategoryDialog(title: "Add under \"\(parent.name)\"") { name, icon, color in
                Task { await create(name: name, icon: icon, color: color, parentId: parent.id) }
            }
        }
        // Edit
        .sheet(item: $editingCategory) { cat in
            CategoryDialog(
                title: "Edit \"\(cat.name)\"",
                initialName: cat.name,
                initialIcon: cat.icon ?? "",
                initialColor: cat.color ?? ""
            ) { name, icon, color in
                Task { await update(id: cat.id, name: name, icon: icon, color: color, parentId: cat.parentId) }
            }
        }
        // Tags
        .sheet(item: $taggingCategory) { cat in
            TagPickerSheet(
                allTags: allTags,
                initialSelectedIds: Set(cat.ownTagIds()),
                readOnly: cat.inheritedTags,
                onCreateTag: { req in
                    guard let created = try? await tagService.createTag(req) else { return nil }
                    let tag = TagResponse(id: created.id, name: req.name, color: req.color, isGlobal: false,
                                           isOwn: true, isActive: true, sortOrder: req.sortOrder ?? 0)
                    allTags.append(tag)
                    return tag
                },
                onSave: { ids in Task { await setTags(id: cat.id, tagIds: Array(ids)) } }
            )
        }
    }

    private func load() async {
        isLoading = true
        async let cats = service.getCategories()
        async let tags = tagService.getTags()
        do {
            let (c, t) = try await (cats, tags)
            categories = c
            allTags = t
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func create(name: String, icon: String?, color: String?, parentId: String?) async {
        do {
            _ = try await service.createCategory(CategoryRequest(name: name, icon: icon, color: color, parentId: parentId))
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func update(id: String, name: String, icon: String?, color: String?, parentId: String?) async {
        do {
            _ = try await service.updateCategory(id: id, req: CategoryRequest(name: name, icon: icon, color: color, parentId: parentId))
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func delete(id: String) async {
        do {
            try await service.deleteCategory(id: id)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func setTags(id: String, tagIds: [String]) async {
        do {
            try await service.setTags(id: id, tagIds: tagIds)
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Accordion card

private struct AccordionCategoryCard: View {
    let category: Category
    let depth: Int
    let onEdit: (Category) -> Void
    let onAddChild: (Category) -> Void
    let onDelete: (Category) -> Void
    var onEditTags: ((Category) -> Void)? = nil

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let icon = category.icon, !icon.isEmpty {
                            Text(icon).font(.title3)
                        }
                        Text(category.name)
                            .font(depth == 0 ? .subheadline.bold() : .subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !category.children.isEmpty {
                            Text("\(category.children.count)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        // Edit
                        if category.isOwn {
                            actionButton("pencil", color: .secondary) { onEdit(category) }
                            actionButton("trash", color: .red) { onDelete(category) }
                        }
                        if let onEditTags {
                            actionButton("tag", color: .secondary) { onEditTags(category) }
                        }
                        actionButton("plus", color: Color.accentColor) { onAddChild(category) }

                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    let shown = effectiveTags(own: category.tags, inherited: category.inheritedTags)
                    if !shown.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(shown) { TagChip(tag: $0) }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Children
            if expanded {
                Divider()
                if category.children.isEmpty {
                    Text("No sub-categories yet")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(category.children) { child in
                        Divider().padding(.leading, CGFloat(16 + (depth + 1) * 16))
                        childRow(child, depth: depth + 1)
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func childRow(_ child: Category, depth: Int) -> some View {
        AccordionCategoryCard(
            category: child,
            depth: depth,
            onEdit: onEdit,
            onAddChild: onAddChild,
            onDelete: onDelete,
            onEditTags: onEditTags
        )
        .background(Color.clear)
        .padding(.leading, CGFloat(depth * 16))
    }

    private func actionButton(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Dialog (Add / Edit)

struct CategoryDialog: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var initialName: String = ""
    var initialIcon: String = ""
    var initialColor: String = ""
    let onConfirm: (String, String?, String?) -> Void

    @State private var name: String
    @State private var icon: String
    @State private var pickedColor: Color
    @State private var isSuggesting = false
    @State private var suggestError: String?

    private var aiAvailable: Bool {
        AiKeyStore.shared.categoriesAiEnabled && LlmClientFactory.shared.hasKey(for: .categoryStyle)
    }

    init(title: String, initialName: String = "", initialIcon: String = "",
         initialColor: String = "", onConfirm: @escaping (String, String?, String?) -> Void) {
        self.title = title; self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
        _icon = State(initialValue: initialIcon)
        _pickedColor = State(initialValue: initialColor.isEmpty ? .accentColor : Color.fromHex(initialColor))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name *", text: $name)
                    TextField("Icon (emoji)", text: $icon)
                    ColorPicker("Color", selection: $pickedColor, supportsOpacity: false)
                    ColorSwatchPicker(hex: Binding(
                        get: { pickedColor.toHex() },
                        set: { pickedColor = Color.fromHex($0) }
                    ))
                    if aiAvailable {
                        Button {
                            Task { await suggestStyle() }
                        } label: {
                            if isSuggesting { ProgressView() } else { Label("Populate using AI", systemImage: "sparkles") }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSuggesting)
                    }
                    if let suggestError {
                        Text(suggestError).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        let trimmedIcon = icon.trimmingCharacters(in: .whitespaces)
                        onConfirm(trimmedName,
                                  trimmedIcon.isEmpty ? nil : trimmedIcon,
                                  pickedColor.toHex())
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func suggestStyle() async {
        isSuggesting = true
        suggestError = nil
        do {
            let suggestion = try await CategoryStyleSuggester.suggest(name: name.trimmingCharacters(in: .whitespaces))
            if let icon = suggestion.icon { self.icon = icon }
            if let color = suggestion.color { pickedColor = Color.fromHex(color) }
        } catch {
            suggestError = AiErrors.message(for: error, provider: LlmClientFactory.shared.provider(for: .categoryStyle))
        }
        isSuggesting = false
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
