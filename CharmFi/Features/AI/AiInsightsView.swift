import SwiftUI

struct AiInsightsView: View {
    @Environment(AuthState.self) private var authState
    @State private var vm: AiInsightsViewModel?
    @State private var composerText = ""

    var body: some View {
        Group {
            if let vm {
                content(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("AI Insights")
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveReadableWidth()
        .toolbar {
            if let vm {
                ToolbarItem(placement: .primaryAction) {
                    Button { vm.clear() } label: { Image(systemName: "trash") }
                }
            }
        }
        .task {
            let model = AiInsightsViewModel(auth: authState)
            vm = model
        }
    }

    @ViewBuilder
    private func content(vm: AiInsightsViewModel) -> some View {
        VStack(spacing: 0) {
            Picker("Period", selection: Binding(get: { vm.period }, set: { vm.period = $0 })) {
                ForEach(AiPeriod.allCases) { p in Text(p.rawValue).tag(p) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            if !vm.hasKey {
                keyMissingView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let err = vm.error {
                                ErrorBannerView(message: err) { vm.error = nil }
                            }
                            if vm.messages.isEmpty {
                                suggestionsView(vm: vm)
                            }
                            ForEach(vm.messages) { message in
                                bubble(message).id(message.id)
                            }
                            if let pending = vm.pendingConfirmation {
                                PendingActionCard(toolName: pending.toolName, summary: pending.summary, decide: pending.decide)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: vm.messages.count) { _, _ in
                        if let last = vm.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }

                composer(vm: vm)
            }
        }
    }

    private var keyMissingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key").font(.largeTitle).foregroundStyle(.secondary)
            Text("Add an API key to use AI Insights").font(.subheadline)
            NavigationLink(destination: AiSettingsView()) {
                Text("Add API key").font(.subheadline.bold())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func suggestionsView(vm: AiInsightsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking").font(.caption).foregroundStyle(.secondary)
            ForEach(AiInsightsViewModel.suggestions, id: \.self) { s in
                Button { vm.send(s) } label: {
                    Text(s).font(.caption)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: DisplayMessage) -> some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !message.thinking.isEmpty && message.isStreaming {
                    Text(String(message.thinking.suffix(240)))
                        .font(.caption2.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                ForEach(message.toolActivity) { activity in
                    HStack(spacing: 6) {
                        Image(systemName: activity.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(activity.ok ? .green : .red)
                            .font(.caption)
                        Text(activity.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if message.isStreaming && message.text.isEmpty && message.toolActivity.isEmpty {
                    TypingDots()
                } else if !message.text.isEmpty {
                    HStack(alignment: .top) {
                        MarkdownView(text: message.text)
                        Spacer(minLength: 0)
                    }
                    if !message.isStreaming {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Image(systemName: "doc.on.doc").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func composer(vm: AiInsightsViewModel) -> some View {
        HStack(spacing: 8) {
            TextField("Ask about your spending…", text: $composerText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18))
                .disabled(vm.pendingConfirmation != nil)
            Button {
                let text = composerText
                composerText = ""
                vm.send(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(composerText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isBusy || vm.pendingConfirmation != nil)
        }
        .padding(12)
    }
}

private struct TypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(.secondary).frame(width: 5, height: 5)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

private struct PendingActionCard: View {
    let toolName: String
    let summary: String
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Apply this change?").font(.subheadline.bold())
            }
            Text(summary).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { decide(false) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Apply") { decide(true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }
}
