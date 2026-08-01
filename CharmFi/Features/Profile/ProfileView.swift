import SwiftUI

struct ProfileView: View {
    @Environment(AuthState.self) private var authState
    @State private var profile: UserProfile?
    @State private var displayName = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var isAdvancedUser = false
    @State private var isSaving = false
    @State private var error: String?

    private var service: UserService { UserService(auth: authState) }

    var body: some View {
        Form {
            Section("Account") {
                if let email = profile?.email {
                    LabeledContent("Email", value: email)
                }
            }
            Section("Display Name") {
                TextField("Your name", text: $displayName)
            }
            Section("Timezone") {
                Picker("Timezone", selection: $timezone) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { tz in
                        Text(tz).tag(tz)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Section("Advanced") {
                Toggle("Advanced mode", isOn: $isAdvancedUser)
                Text("Enables AND/OR matching in Merchant Rules")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
            Section {
                Button("Save Changes") { Task { await save() } }
                    .disabled(isSaving)
            }
        }
        .navigationTitle("Profile")
        .adaptiveReadableWidth()
        .task { await load() }
    }

    private func load() async {
        do {
            profile = try await service.getProfile()
            displayName = profile?.displayName ?? authState.displayName ?? ""
            timezone = profile?.timezone ?? TimeZone.current.identifier
            isAdvancedUser = profile?.isAdvancedUser ?? false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        do {
            let req = UpdateUserRequest(displayName: displayName.isEmpty ? nil : displayName, timezone: timezone, isAdvancedUser: isAdvancedUser)
            profile = try await service.updateProfile(req)
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
