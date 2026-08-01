import SwiftUI

/// Multi-select sheet over the full tag list, with a read-only section (inherited tags) above a
/// divider and an optional inline "create tag" row. Mirrors Android's `TagPickerSheet`. The
/// caller owns persistence — `onSave` fires with the complete desired working set (a whole-set
/// replace, not a delta).
struct TagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let allTags: [TagResponse]
    let initialSelectedIds: Set<String>
    var readOnly: [TagRef] = []
    var readOnlyCaption: String = "Inherited — change these on the parent category"
    var allowCreate: Bool = true
    var onCreateTag: ((TagRequest) async -> TagResponse?)? = nil
    var onSave: (Set<String>) -> Void

    @State private var selected: Set<String>
    @State private var newTagName = ""
    @State private var newTagColor = "#64748b"
    @State private var showCreateRow = false
    @State private var isCreating = false
    @State private var workingTags: [TagResponse]

    init(allTags: [TagResponse], initialSelectedIds: Set<String>, readOnly: [TagRef] = [],
         readOnlyCaption: String = "Inherited — change these on the parent category",
         allowCreate: Bool = true,
         onCreateTag: ((TagRequest) async -> TagResponse?)? = nil,
         onSave: @escaping (Set<String>) -> Void) {
        self.allTags = allTags
        self.initialSelectedIds = initialSelectedIds
        self.readOnly = readOnly
        self.readOnlyCaption = readOnlyCaption
        self.allowCreate = allowCreate
        self.onCreateTag = onCreateTag
        self.onSave = onSave
        _selected = State(initialValue: initialSelectedIds)
        _workingTags = State(initialValue: allTags)
    }

    var body: some View {
        NavigationStack {
            List {
                if !readOnly.isEmpty {
                    Section(readOnlyCaption) {
                        FlowTagRow(tags: readOnly)
                    }
                }
                Section("Tags") {
                    ForEach(workingTags.filter(\.isActive)) { tag in
                        Button {
                            if selected.contains(tag.id) { selected.remove(tag.id) }
                            else { selected.insert(tag.id) }
                        } label: {
                            HStack {
                                Circle().fill(Color.fromHex(tag.color)).frame(width: 10, height: 10)
                                Text(tag.name).foregroundStyle(.primary)
                                if tag.isGlobal {
                                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                    if allowCreate {
                        if showCreateRow {
                            createRow
                        } else {
                            Button {
                                showCreateRow = true
                            } label: {
                                Label("New tag", systemImage: "plus.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(selected); dismiss() }
                }
            }
        }
    }

    private var createRow: some View {
        HStack {
            Circle().fill(Color.fromHex(newTagColor)).frame(width: 16, height: 16)
                .onTapGesture { cycleColor() }
            TextField("Tag name", text: $newTagName)
            if isCreating {
                ProgressView()
            } else {
                Button("Add") { Task { await createTag() } }
                    .disabled(newTagName.isEmpty)
            }
        }
    }

    private func cycleColor() {
        let palette = ColorSwatchPicker.palette
        if let idx = palette.firstIndex(where: { $0.caseInsensitiveCompare(newTagColor) == .orderedSame }) {
            newTagColor = palette[(idx + 1) % palette.count]
        } else {
            newTagColor = palette[0]
        }
    }

    private func createTag() async {
        guard let onCreateTag, !newTagName.isEmpty else { return }
        isCreating = true
        if let created = await onCreateTag(TagRequest(name: newTagName, color: newTagColor, sortOrder: nil)) {
            workingTags.append(created)
            selected.insert(created.id)
            newTagName = ""
            showCreateRow = false
        }
        isCreating = false
    }
}

/// Wraps a list of read-only tag chips onto multiple lines.
private struct FlowTagRow: View {
    let tags: [TagRef]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 70), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(tags) { TagChip(tag: $0) }
        }
    }
}
