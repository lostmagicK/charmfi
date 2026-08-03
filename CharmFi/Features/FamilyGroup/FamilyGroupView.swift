import SwiftUI

struct FamilyGroupView: View {
    @Environment(AuthState.self) private var authState
    @State private var group: FamilyGroup?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var newGroupName = ""
    @State private var inviteCode = ""
    @State private var joinDisplayName = ""

    private var service: FamilyGroupService { FamilyGroupService(auth: authState) }

    var body: some View {
        // Above the switch: a failed fetch leaves `group` nil, and "no group" is a legitimate state,
        // so without this a broken load reads as "you aren't in a family group".
        VStack(spacing: 0) {
            if let error {
                ErrorBannerView(message: error) { self.error = nil }
            }
            if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let group {
                groupContent(group)
            } else {
                noGroupContent
            }
        }
        .navigationTitle("Family Group")
        .adaptiveReadableWidth()
        .task { await load() }
        .alert("Create Group", isPresented: $showCreate) {
            TextField("Group Name", text: $newGroupName)
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Join Group", isPresented: $showJoin) {
            TextField("Invite Code", text: $inviteCode)
            TextField("Your Display Name", text: $joinDisplayName)
            Button("Join") { Task { await join() } }
                .disabled(inviteCode.isEmpty || joinDisplayName.isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var noGroupContent: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.3").font(.system(size: 60)).foregroundStyle(.secondary)
            Text("No Family Group").font(.title2.bold())
            Text("Create a group or join one with an invite code").foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Create Group") { showCreate = true }
                    .buttonStyle(.borderedProminent)
                Button("Join Group") { showJoin = true }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }

    private func groupContent(_ group: FamilyGroup) -> some View {
        List {
            Section("Group") {
                LabeledContent("Name", value: group.name)
                HStack {
                    LabeledContent("Invite Code", value: group.inviteCode)
                    Button { UIPasteboard.general.string = group.inviteCode } label: {
                        Image(systemName: "doc.on.doc").foregroundStyle(Color.accentColor)
                    }
                }
            }
            Section("Members (\(group.members.count))") {
                ForEach(group.members) { member in
                    HStack {
                        Image(systemName: "person.circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(member.displayName).font(.subheadline)
                            Text(member.role.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if member.userId == authState.userId {
                            Text("You").font(.caption).foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            Section {
                Button("Leave Group", role: .destructive) { Task { await leave() } }
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            group = try await service.getGroup()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func create() async {
        guard !newGroupName.isEmpty else { return }
        do {
            group = try await service.createGroup(name: newGroupName)
        } catch { self.error = error.localizedDescription }
    }

    private func join() async {
        guard !inviteCode.isEmpty, !joinDisplayName.isEmpty else { return }
        do {
            group = try await service.joinGroup(inviteCode: inviteCode, displayName: joinDisplayName)
        } catch { self.error = error.localizedDescription }
    }

    private func leave() async {
        do {
            try await service.leaveGroup()
            group = nil
        } catch { self.error = error.localizedDescription }
    }
}
