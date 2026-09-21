import OtohaChatKit
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var keyDrafts: [UUID: String] = [:]
    @State private var showingImporter = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            providersSection
            appleStatusSection
            workspaceSection
            skillsSection
            if store.fixtureEnabled {
                Section("Developer") {
                    Button("Open fixture chat") {
                        _ = store.createFixtureConversation()
                    }
                    Text("Fixture chats are explicit. Ordinary conversations never fall back to the fixture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if let statusMessage {
                Section {
                    CopyableBanner(
                        text: statusMessage,
                        systemImage: statusMessageLooksLikeError ? "exclamationmark.triangle.fill" : "checkmark.circle",
                        tint: statusMessageLooksLikeError ? .orange : .secondary,
                        font: .caption
                    )
                }
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Settings")
        .onAppear { store.refreshReadyCatalogsIfNeeded() }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                store.setWorkspace(url)
            }
        }
    }

    private var providersSection: some View {
        Section {
            ForEach(store.settings.profiles) { profile in
                providerCard(profile)
            }
        } header: {
            Text("Providers")
        } footer: {
            Text("Turn a provider on and add its API key to list its models. Closed providers stay out of the model switcher.")
        }
    }

    private var appleStatusSection: some View {
        Section("Apple runtime") {
            LabeledContent("On-device") {
                CopyableText(text: store.onDeviceStatus.title, showsCopyButton: true)
            }
            CopyableText(
                text: store.onDeviceStatus.detail,
                font: .caption,
                color: .secondary,
                showsCopyButton: true
            )
            LabeledContent("Private Cloud Compute") {
                CopyableText(text: store.pccStatus.title, showsCopyButton: true)
            }
            CopyableText(
                text: store.pccStatus.detail,
                font: .caption,
                color: .secondary,
                showsCopyButton: true
            )
            CopyableText(
                text: "PCC needs a signed build with Apple’s entitlement. Availability is read from the running system, not from the entitlements file.",
                font: .caption,
                color: .secondary
            )
        }
    }

    @ViewBuilder
    private func providerCard(_ profile: ProviderProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: enabledBinding(profile.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(statusCaption(profile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("Enable \(profile.displayName)")

            if profile.isEnabled {
                enabledProviderDetails(profile)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func enabledProviderDetails(_ profile: ProviderProfile) -> some View {
        if profile.kind.requiresAPIKey {
            SecureField("API key", text: draftBinding(profile.id))
            HStack {
                Button("Save key") {
                    let secret = keyDrafts[profile.id, default: ""]
                    do {
                        try store.setAPIKey(profileID: profile.id, secret: secret)
                        keyDrafts[profile.id] = ""
                        statusMessage = "Key saved. Fetching models for \(profile.displayName)."
                    } catch {
                        statusMessage = error.localizedDescription
                    }
                }
                .disabled(keyDrafts[profile.id, default: ""].isEmpty)
                Button("Delete key", role: .destructive) {
                    try? store.deleteAPIKey(profileID: profile.id)
                    statusMessage = "Key deleted for \(profile.displayName)."
                }
                Spacer()
                Text(store.hasAPIKey(profileID: profile.id) ? "Key on file" : "No key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        if profile.kind.usesHTTP {
            DisclosureGroup("Endpoint") {
                TextField("Endpoint URL", text: urlBinding(profile.id))
                TextField("Catalog URL", text: catalogBinding(profile.id))
                Toggle("Allow unauthenticated local access", isOn: unauthBinding(profile.id))
                Toggle("Allow private-network HTTP", isOn: lanBinding(profile.id))
            }
        }

        if profile.kind == .localResponses
            || profile.kind == .compatibleGateway
            || profile.kind == .anthropic
        {
            TextField("Model ID", text: modelBinding(profile.id))
        }

        HStack {
            Button {
                Task {
                    await store.refreshCatalog(profileID: profile.id)
                    statusMessage = catalogStatusMessage(profile.id)
                }
            } label: {
                if store.refreshingCatalogIDs.contains(profile.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Refresh models")
                }
            }
            .disabled(store.refreshingCatalogIDs.contains(profile.id))
            Spacer()
            Text(catalogCaption(profile))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if profile.catalogStale {
            CopyableText(
                text: "Catalog is stale. Last known models were kept.",
                font: .caption,
                color: .orange
            )
        }
        if let error = profile.lastCatalogError {
            CopyableBanner(
                text: error,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                font: .caption
            )
        }

        if !profile.pickerModels.isEmpty {
            DisclosureGroup("Models (\(profile.pickerModels.count))") {
                ForEach(Array(profile.pickerModels.prefix(40))) { model in
                    VStack(alignment: .leading, spacing: 2) {
                        CopyableText(text: model.title, font: .body)
                        if !model.parameterSummary.isEmpty {
                            CopyableText(
                                text: model.parameterSummary,
                                font: .caption2,
                                color: .secondary
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                if profile.pickerModels.count > 40 {
                    CopyableText(
                        text: "\(profile.pickerModels.count - 40) more in the model switcher.",
                        font: .caption,
                        color: .secondary
                    )
                }
            }
        }
    }

    private func statusCaption(_ profile: ProviderProfile) -> String {
        if !profile.isEnabled { return "Off" }
        switch profile.kind {
        case .applePCC:
            return store.pccStatus.title
        case .appleOnDevice:
            return store.onDeviceStatus.title
        case .localResponses:
            return profile.endpointIsConfigured ? "Ready" : "Add an endpoint"
        case .openaiResponses, .anthropic, .deepseekResponses, .compatibleGateway:
            if !store.hasAPIKey(profileID: profile.id) { return "Add an API key" }
            if profile.pickerModels.isEmpty { return "Key on file" }
            return "\(profile.pickerModels.count) models"
        }
    }

    private func catalogCaption(_ profile: ProviderProfile) -> String {
        if store.refreshingCatalogIDs.contains(profile.id) { return "Refreshing…" }
        if profile.pickerModels.isEmpty { return "No models yet" }
        return "\(profile.pickerModels.count) from catalog"
    }

    private func catalogStatusMessage(_ id: UUID) -> String {
        guard let profile = store.settings.profiles.first(where: { $0.id == id }) else {
            return "Catalog refresh finished."
        }
        if let error = profile.lastCatalogError { return error }
        return "Loaded \(profile.pickerModels.count) models for \(profile.displayName)."
    }

    private var statusMessageLooksLikeError: Bool {
        guard let statusMessage else { return false }
        let lowered = statusMessage.lowercased()
        return lowered.contains("error")
            || lowered.contains("fail")
            || lowered.contains("invalid")
            || lowered.contains("unable")
            || lowered.contains("denied")
            || store.settings.profiles.contains { $0.lastCatalogError == statusMessage }
    }

    private var workspaceSection: some View {
        Section("Workspace") {
            LabeledContent("Folder") {
                CopyableText(
                    text: store.workspaceURL?.path ?? "None",
                    color: .secondary,
                    showsCopyButton: store.workspaceURL != nil
                )
            }
            Button("Choose workspace…") { chooseWorkspace() }
            Button("Clear workspace", role: .destructive) { store.setWorkspace(nil) }
            CopyableText(
                text: "Skills load from the authorized folder’s .agents/skills directory.",
                font: .caption,
                color: .secondary
            )
        }
    }

    private var skillsSection: some View {
        Section("Skills") {
            if store.skills.isEmpty {
                CopyableText(
                    text: "No skills discovered. Authorize a workspace that contains .agents/skills.",
                    color: .secondary
                )
            } else {
                ForEach(store.skills) { skill in
                    VStack(alignment: .leading, spacing: 4) {
                        CopyableText(text: skill.name, font: .headline)
                        CopyableText(text: skill.description, font: .caption, color: .secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            Button("Refresh skills") { store.refreshSkills() }
        }
    }

    private func draftBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { keyDrafts[id, default: ""] },
            set: { keyDrafts[id] = $0 }
        )
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.settings.profiles.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { store.setProviderEnabled(profileID: id, enabled: $0) }
        )
    }

    private func urlBinding(_ id: UUID) -> Binding<String> {
        binding(id, get: { $0.executionURL ?? "" }, set: { $0.executionURL = $1 })
    }

    private func catalogBinding(_ id: UUID) -> Binding<String> {
        binding(id, get: { $0.catalogURL ?? "" }, set: { $0.catalogURL = $1 })
    }

    private func modelBinding(_ id: UUID) -> Binding<String> {
        binding(id, get: \.manualModelID) { profile, value in
            profile.manualModelID = value
            profile.selectedModelID = value
        }
    }

    private func unauthBinding(_ id: UUID) -> Binding<Bool> {
        binding(id, get: \.allowsUnauthenticated) { $0.allowsUnauthenticated = $1 }
    }

    private func lanBinding(_ id: UUID) -> Binding<Bool> {
        binding(id, get: \.allowsInsecurePrivateNetworkHTTP) { $0.allowsInsecurePrivateNetworkHTTP = $1 }
    }

    private func binding<T>(
        _ id: UUID,
        get: @escaping (ProviderProfile) -> T,
        set: @escaping (inout ProviderProfile, T) -> Void
    ) -> Binding<T> {
        Binding(
            get: {
                guard let profile = store.settings.profiles.first(where: { $0.id == id }) else {
                    return get(ProviderProfile(kind: .openaiResponses))
                }
                return get(profile)
            },
            set: { value in
                guard let index = store.settings.profiles.firstIndex(where: { $0.id == id }) else { return }
                var document = store.settings
                set(&document.profiles[index], value)
                try? store.saveSettings(document)
            }
        )
    }

    private func chooseWorkspace() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Authorize"
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            store.setWorkspace(url)
        }
        #else
        showingImporter = true
        #endif
    }
}
