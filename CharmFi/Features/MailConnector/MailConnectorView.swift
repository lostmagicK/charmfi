import SwiftUI
import SwiftData

struct MailConnectorView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @State private var vm: MailConnectorViewModel?
    @State private var selectedFailedEmail: FailedScanEmail?

    var body: some View {
        Group {
            if let vm {
                mailConnectorContent(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Mail Connector")
        .adaptiveReadableWidth()
        .task {
            vm = ViewModelStore.shared.model(MailConnectorViewModel.self, auth: authState) {
                $0.setModelContext(modelContext)
            }.model
        }
    }

    @ViewBuilder
    private func mailConnectorContent(vm: MailConnectorViewModel) -> some View {
        List {
            connectionSection(vm: vm)
            if vm.isSignedIn {
                syncSection(vm: vm)
                progressSection(vm: vm)
                failedEmailsSection(vm: vm)
            }
            privacyNote
        }
    }

    private func connectionSection(vm: MailConnectorViewModel) -> some View {
        Section("Gmail Connection") {
            if vm.isSignedIn {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Connected").font(.subheadline.bold())
                    }
                    if let email = vm.googleEmail {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                    if let lastSync = vm.lastSyncDate {
                        Text("Last sync: \(lastSync.shortDateString)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("Disconnect Gmail", role: .destructive) { vm.signOut() }
            } else {
                Button {
                    Task { await vm.signIn() }
                } label: {
                    HStack {
                        Image(systemName: "envelope.badge")
                        Text("Connect Gmail Account")
                    }
                }
            }
        }
    }

    private func syncSection(vm: MailConnectorViewModel) -> some View {
        Section("Sync Settings") {
            DatePicker("Sync emails since", selection: Bindable(vm).sinceDate, displayedComponents: .date)
            Button {
                Task { await vm.startSync() }
            } label: {
                HStack {
                    if vm.isSyncing {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(vm.isSyncing ? "Syncing..." : "Sync Now")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(vm.isSyncing)
            .buttonStyle(.borderedProminent)

            Button("Clear Scan History", role: .destructive) {
                vm.clearScanHistory()
            }
            .disabled(vm.isSyncing)
        }
    }

    @ViewBuilder
    private func progressSection(vm: MailConnectorViewModel) -> some View {
        switch vm.syncProgress {
        case .idle:
            EmptyView()
        case .running(let message):
            Section("Progress") {
                HStack {
                    ProgressView()
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .destructive) { vm.cancelSync() }
                        .font(.caption)
                }
            }
        case .completed(let created, let failed):
            Section("Last Sync Result") {
                if created > 0 {
                    Label("\(created) draft expense\(created == 1 ? "" : "s") created", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if failed > 0 {
                    Label("\(failed) email\(failed == 1 ? "" : "s") failed to process", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if created == 0 && failed == 0 {
                    Label("No new expenses found", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                Text("Check Inbox to review and approve").font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let error):
            Section("Error") {
                Label(error, systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func failedEmailsSection(vm: MailConnectorViewModel) -> some View {
        if !vm.failedEmails.isEmpty {
            Section {
                ForEach(vm.failedEmails) { failed in
                    Button {
                        selectedFailedEmail = failed
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failed.subject.isEmpty ? "(No subject)" : failed.subject)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                if let amount = failed.parsedAmount {
                                    Text("₹\(String(format: "%.0f", amount))")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                }
                                if let merchant = failed.parsedMerchant {
                                    Text(merchant)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(failed.errorMessage)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Label("\(vm.failedEmails.count) Failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } footer: {
                Text("Tap an email to view its parsed content and debug the pattern.")
            }
            .sheet(item: $selectedFailedEmail) { failed in
                FailedEmailDetailView(email: failed)
            }
        }
    }

    private var privacyNote: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Color.accentColor)
                Text("Your Google credentials stay on this device and are never sent to CharmFi servers. Only matched expense data is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
