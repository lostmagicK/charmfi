import SwiftUI

struct AiSettingsView: View {
    @Environment(AuthState.self) private var authState
    @State private var tab = 0
    // Deliberately empty rather than seeded from the Keychain: a saved key is never read back into
    // the UI, so it can't be shoulder-surfed or screenshotted out of Settings. The field replaces a
    // key, it doesn't display one. Matches Android's `ProviderKeySection`.
    @State private var anthropicKey = ""
    @State private var googleKey = ""
    @State private var revealAnthropic = false
    @State private var revealGoogle = false
    @State private var savedNotice: String?
    /// Redrawn on save/remove so the "a key is saved" chips reflect the store.
    @State private var keyRevision = 0
    @State private var models: [AiModelOption] = AiModelCatalogRepository.shared.cachedModels
    @State private var selectedModels: [AiUseCase: String] = Dictionary(
        uniqueKeysWithValues: AiUseCase.allCases.map { ($0, LlmClientFactory.shared.model(for: $0)) }
    )
    @State private var categoriesAiEnabled = AiKeyStore.shared.categoriesAiEnabled

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("General").tag(0)
                Text("Models").tag(1)
                Text("Features").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            switch tab {
            case 0: generalTab
            case 1: modelsTab
            default: featuresTab
            }
            Spacer()
        }
        .navigationTitle("AI Settings")
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveReadableWidth()
        .task {
            models = await AiModelCatalogRepository.shared.sync(auth: authState)
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Text("Your keys are stored encrypted on this device only. Each is sent directly to its provider when you request analysis, and never to the CharmFI server.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            keySection(provider: .anthropic, key: $anthropicKey, reveal: $revealAnthropic)
            keySection(provider: .google, key: $googleKey, reveal: $revealGoogle)
            if let savedNotice {
                Section { Text(savedNotice).font(.caption).foregroundStyle(.green) }
            }
        }
    }

    private func keySection(provider: AiProvider, key: Binding<String>, reveal: Binding<Bool>) -> some View {
        // Reading the counter is what subscribes this section to save/remove — the store itself
        // isn't observable.
        _ = keyRevision
        let hasKey = AiKeyStore.shared.hasKey(for: provider)
        return Section(provider.displayName) {
            if hasKey {
                Label("A key is saved on this device", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Group {
                    let prompt = hasKey ? "Replace key (\(provider.keyHint))" : "Paste key (\(provider.keyHint))"
                    if reveal.wrappedValue { TextField(prompt, text: key) }
                    else { SecureField(prompt, text: key) }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                // Reveals only what's being typed now — there is nothing saved to reveal.
                Button { reveal.wrappedValue.toggle() } label: {
                    Image(systemName: reveal.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Button("Save") {
                    AiKeyStore.shared.setApiKey(key.wrappedValue, for: provider)
                    key.wrappedValue = ""
                    reveal.wrappedValue = false
                    keyRevision += 1
                    savedNotice = "\(provider.displayName) key saved"
                }
                .disabled(key.wrappedValue.isEmpty)
                .buttonStyle(.borderless)
                Spacer()
                if hasKey {
                    Button("Remove key", role: .destructive) {
                        key.wrappedValue = ""
                        AiKeyStore.shared.setApiKey(nil, for: provider)
                        keyRevision += 1
                        savedNotice = "\(provider.displayName) key removed"
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var modelsTab: some View {
        Form {
            ForEach(AiUseCase.allCases, id: \.self) { useCase in
                Section {
                    Picker(useCase.title, selection: Binding(
                        get: { selectedModels[useCase] ?? useCase.defaultModelId },
                        set: { newValue in
                            selectedModels[useCase] = newValue
                            AiKeyStore.shared.setModel(newValue, for: useCase)
                        }
                    )) {
                        ForEach(groupedByProvider, id: \.provider) { group in
                            Section(group.provider.displayName) {
                                ForEach(group.models) { m in Text(m.label).tag(m.id) }
                            }
                        }
                    }
                    Text(useCase.description).font(.caption).foregroundStyle(.secondary)
                    let provider = AiModelCatalogRepository.shared.provider(of: selectedModels[useCase] ?? useCase.defaultModelId)
                    if !AiKeyStore.shared.hasKey(for: provider) {
                        Label("No \(provider.displayName) key saved — add one in General.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var groupedByProvider: [(provider: AiProvider, models: [AiModelOption])] {
        AiProvider.allCases.map { p in (provider: p, models: models.filter { $0.provider == p }) }
            .filter { !$0.models.isEmpty }
    }

    private var featuresTab: some View {
        Form {
            Section {
                Toggle("Auto-populate icon & color", isOn: Binding(
                    get: { categoriesAiEnabled },
                    set: { categoriesAiEnabled = $0; AiKeyStore.shared.categoriesAiEnabled = $0 }
                ))
            } footer: {
                Text("Suggests an emoji and color when you create a category, using the Category icon & color model above.")
            }
        }
    }
}
