import SwiftUI

struct TagsView: View {
    @Environment(AuthState.self) private var authState
    @State private var vm: TagsViewModel?
    @State private var showAdd = false
    @State private var editingTag: TagResponse?
    @State private var deletingTag: TagResponse?

    var body: some View {
        Group {
            if let vm {
                if vm.isLoading && vm.tags.isEmpty {
                    ProgressView()
                } else if vm.activeTags.isEmpty {
                    ContentUnavailableView("No Tags", systemImage: "tag",
                                            description: Text("Tags cut across categories — group expenses by trip, project or anything else that doesn't map to a category tree."))
                } else {
                    List {
                        if let err = vm.error {
                            ErrorBannerView(message: err) { vm.error = nil }
                        }
                        ForEach(vm.activeTags) { tag in
                            HStack {
                                TagChip(tag: TagRef(id: tag.id, name: tag.name, color: tag.color, isGlobal: tag.isGlobal))
                                Spacer()
                                if tag.isGlobal {
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                } else {
                                    Button { editingTag = tag } label: { Image(systemName: "pencil") }
                                        .buttonStyle(.borderless)
                                    Button(role: .destructive) { deletingTag = tag } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Tags")
        .adaptiveReadableWidth()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .task {
            let model = TagsViewModel(auth: authState)
            vm = model
            await model.load()
        }
        .refreshable { await vm?.load() }
        .sheet(isPresented: $showAdd) {
            if let vm { TagFormSheet(vm: vm, tag: nil) }
        }
        .sheet(item: $editingTag) { tag in
            if let vm { TagFormSheet(vm: vm, tag: tag) }
        }
        .confirmationDialog(
            "Delete this tag? It's removed from every category, merchant rule and transaction that uses it.",
            isPresented: Binding(get: { deletingTag != nil }, set: { if !$0 { deletingTag = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletingTag { Task { await vm?.deleteTag(id: deletingTag.id) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct TagFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: TagsViewModel
    let tag: TagResponse?

    @State private var name = ""
    @State private var color = "#64748b"

    init(vm: TagsViewModel, tag: TagResponse?) {
        self.vm = vm; self.tag = tag
        if let tag {
            _name = State(initialValue: tag.name)
            _color = State(initialValue: tag.color)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Color") {
                    ColorSwatchPicker(hex: $color)
                }
                Section("Preview") {
                    TagChip(tag: TagRef(id: "preview", name: name.isEmpty ? "Tag" : name, color: color))
                }
            }
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let req = TagRequest(name: name, color: color, sortOrder: tag?.sortOrder)
                        Task {
                            if let tag { await vm.updateTag(id: tag.id, req: req) }
                            else { await vm.createTag(req) }
                            dismiss()
                        }
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
