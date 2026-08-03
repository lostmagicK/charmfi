import SwiftUI

struct SettingsView: View {
    @Environment(AuthState.self) private var authState
    @AppStorage("appColorScheme") private var colorSchemeValue: Int = 0

    var body: some View {
        List {
            Section("Appearance") {
                Picker(selection: $colorSchemeValue) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag(0)
                    Label("Light", systemImage: "sun.max").tag(1)
                    Label("Dark", systemImage: "moon").tag(2)
                } label: {
                    Label("Theme", systemImage: "paintbrush")
                }
            }
            Section("Account") {
                NavigationLink(destination: ProfileView()) {
                    Label("Profile", systemImage: "person.circle")
                }
                NavigationLink(destination: FamilyGroupView()) {
                    Label("Family Group", systemImage: "person.3")
                }
            }
            Section("Manage") {
                NavigationLink(destination: CategoriesView()) {
                    Label("Categories", systemImage: "tag")
                }
                NavigationLink(destination: TagsView()) {
                    Label("Tags", systemImage: "number")
                }
            }
            Section("Preferences") {
                NavigationLink(destination: BudgetSettingsView()) {
                    Label("Budget Settings", systemImage: "slider.horizontal.3")
                }
                NavigationLink(destination: AiSettingsView()) {
                    Label("AI Settings", systemImage: "sparkles")
                }
            }
            Section("Integrations") {
                NavigationLink(destination: MailConnectorView()) {
                    Label("Mail Connector", systemImage: "envelope")
                }
            }
            Section {
                Button(role: .destructive) {
                    authState.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
        .adaptiveReadableWidth()
    }
}
