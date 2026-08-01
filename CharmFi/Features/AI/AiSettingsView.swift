import SwiftUI

struct AiSettingsView: View {
    @Environment(AuthState.self) private var authState
    @State private var tab = 0
    @State private var anthropicKey = AiKeyStore.shared.apiKey(for: .anthropic) ?? ""
    @State private var googleKey = AiKeyStore.shared.apiKey(for: .google) ?? ""
    @State private var revealAnthropic = false
    @State private var revealGoogle = false
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
            keySection(provider: .anthropic, key: $anthropicKey, reveal: $revealAnthropic)
            keySection(provider: .google, key: $googleKey, reveal: $revealGoogle)
        }
    }

    private func keySection(provider: AiProvider, key: Binding<String>, reveal: Binding<Bool>) -> some View {
        Section(provider.displayName) {
            HStack {
                Group {
                    if reveal.wrappedValue { TextField(provider.keyHint, text: key) }
                    else { SecureField(provider.keyHint, text: key) }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                Button { reveal.wrappedValue.toggle() } label: {
                    Image(systemName: reveal.wrappedValue ? "eye.slash" : "eye")
                }
            }
            HStack {
                Button("Save") { AiKeyStore.shared.setApiKey(key.wrappedValue, for: provider) }
                    .disabled(key.wrappedValue.isEmpty)
                Spacer()
                Button("Remove key", role: .destructive) {
                    key.wrappedValue = ""
                    AiKeyStore.shared.setApiKey(nil, for: provider)
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
