import OtohaChatKit
import SwiftUI

struct ComposerBar: View {
    @EnvironmentObject private var store: ChatStore
    @Binding var input: String
    var focused: FocusState<Bool>.Binding
    let conversation: ChatSessionSummary
    let compact: Bool
    let send: () -> Void
    let stop: () -> Void

    @State private var showingModelPicker = false
    @State private var pendingSelection: PendingModelSelection?
    @State private var showingSwitchConfirm = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = conversation.inputError {
                CopyableBanner(
                    text: error,
                    systemImage: "exclamationmark.circle",
                    tint: .red,
                    font: .caption
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField(placeholder, text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused(focused)
                    .padding(.horizontal, 4)
                    .onSubmit {
                        if !conversation.snapshot.isBusy, canSend { send() }
                    }
                    .accessibilityLabel("Message")

                HStack(alignment: .center, spacing: 8) {
                    Button {
                        store.shouldOpenSettings = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                            .frame(width: 28, height: 28)
                            .background(OtohaChatTheme.chipFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .accessibilityLabel("Settings")

                    Spacer()

                    modelChip

                    if conversation.snapshot.isBusy {
                        Button(action: stop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: OtohaChatTheme.sendSize, height: OtohaChatTheme.sendSize)
                                .background(Color.primary, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Stop and wait until the run drains")
                        .accessibilityLabel("Stop")
                    } else {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: OtohaChatTheme.sendSize, height: OtohaChatTheme.sendSize)
                                .background(canSend ? Color.primary : Color.primary.opacity(0.28), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Send")
                    }
                }
            }
            .padding(14)
            .background(OtohaChatTheme.canvas, in: RoundedRectangle(cornerRadius: OtohaChatTheme.composerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OtohaChatTheme.composerRadius, style: .continuous)
                    .strokeBorder(OtohaChatTheme.composerStroke)
            )
            .shadow(color: Color.black.opacity(compact ? 0.04 : 0.08), radius: compact ? 8 : 16, y: 6)
        }
        .popover(isPresented: macPopoverPresented, arrowEdge: .bottom) {
            modelPicker(style: .popover)
                .environmentObject(store)
        }
        .sheet(isPresented: compactSheetPresented) {
            NavigationStack {
                modelPicker(style: .sheet)
                    .navigationTitle("Model")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingModelPicker = false }
                        }
                    }
            }
            .environmentObject(store)
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .confirmationDialog(
            "Switch model",
            isPresented: $showingSwitchConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue this chat") {
                applyPending(startNewChat: false)
            }
            Button("Start a new chat") {
                applyPending(startNewChat: true)
            }
            Button("Cancel", role: .cancel) {
                pendingSelection = nil
            }
        } message: {
            Text("The next message can continue here with a semantic handoff, or you can start a new chat.")
        }
    }

    private var usesCompactPicker: Bool {
        #if os(iOS)
        horizontalSizeClass != .regular
        #else
        false
        #endif
    }

    private var macPopoverPresented: Binding<Bool> {
        Binding(
            get: { showingModelPicker && !usesCompactPicker },
            set: { if !$0 { showingModelPicker = false } }
        )
    }

    private var compactSheetPresented: Binding<Bool> {
        Binding(
            get: { showingModelPicker && usesCompactPicker },
            set: { if !$0 { showingModelPicker = false } }
        )
    }

    private func modelPicker(style: ModelPickerPopover.Style) -> some View {
        ModelPickerPopover(
            conversation: conversation,
            onSelect: handleSelection,
            onReasoning: applyCatalogReasoning,
            onOpenSettings: {
                showingModelPicker = false
                store.shouldOpenSettings = true
            },
            style: style
        )
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var placeholder: String {
        "Using \(conversation.modelName)"
    }

    private var profile: ProviderProfile? {
        store.settings.profiles.first(where: { $0.id == conversation.profileID })
    }

    private var modelChip: some View {
        Button {
            showingModelPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(shortModelName)
                    .font(.caption.weight(.medium))
                if let profile, let model = profile.catalogModel(named: conversation.modelName),
                   conversation.reasoning.showsReasoningControls(for: model, kind: profile.kind) {
                    Text(conversation.reasoning.selectedReasoningValue(for: model, kind: profile.kind).capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OtohaChatTheme.chipFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model \(conversation.modelName)")
        .help("Choose a model and reasoning intensity")
        .contextMenu {
            Button("Copy model") {
                Clipboard.copy(conversation.modelName)
            }
        }
    }

    private var shortModelName: String {
        let name = conversation.modelName
        if name.count <= 18 { return name }
        return String(name.suffix(16))
    }

    private func handleSelection(profileID: UUID, modelName: String) {
        showingModelPicker = false
        let reasoning = reasoningForSelection(profileID: profileID, modelName: modelName)
        if store.shouldConfirmModelSwitch(
            conversationID: conversation.id,
            profileID: profileID,
            modelName: modelName
        ) {
            pendingSelection = PendingModelSelection(
                profileID: profileID,
                modelName: modelName,
                reasoning: reasoning
            )
            showingSwitchConfirm = true
            return
        }
        store.updateRunConfiguration(
            conversationID: conversation.id,
            profileID: profileID,
            modelName: modelName,
            reasoning: reasoning
        )
    }

    private func reasoningForSelection(profileID: UUID, modelName: String) -> ReasoningConfiguration {
        guard let selected = store.settings.profiles.first(where: { $0.id == profileID }) else {
            return conversation.reasoning
        }
        return conversation.reasoning.clamped(
            to: selected.catalogModel(named: modelName),
            kind: selected.kind
        )
    }

    private func applyCatalogReasoning(_ value: String) {
        guard var profile = profile else { return }
        var reasoning = conversation.reasoning
        if let model = profile.catalogModel(named: conversation.modelName) {
            reasoning.applyCatalogReasoning(value, model: model, kind: profile.kind)
        }
        store.updateRunConfiguration(
            conversationID: conversation.id,
            profileID: conversation.profileID,
            modelName: conversation.modelName,
            reasoning: reasoning
        )
        profile.reasoning = reasoning
        var document = store.settings
        if let index = document.profiles.firstIndex(where: { $0.id == profile.id }) {
            document.profiles[index] = profile
            try? store.saveSettings(document)
        }
    }

    private func applyPending(startNewChat: Bool) {
        guard let pendingSelection else { return }
        store.applyModelSelection(
            conversationID: conversation.id,
            profileID: pendingSelection.profileID,
            modelName: pendingSelection.modelName,
            reasoning: pendingSelection.reasoning,
            startNewChat: startNewChat
        )
        self.pendingSelection = nil
    }
}

private struct PendingModelSelection {
    var profileID: UUID
    var modelName: String
    var reasoning: ReasoningConfiguration
}

private struct ModelPickerPopover: View {
    @EnvironmentObject private var store: ChatStore
    let conversation: ChatSessionSummary
    let onSelect: (UUID, String) -> Void
    let onReasoning: (String) -> Void
    var onOpenSettings: () -> Void = {}
    var style: Style = .popover
    @State private var query = ""

    enum Style {
        case popover
        case sheet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if style == .popover {
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if visibleProfiles.isEmpty {
                Text("Turn on a provider in Settings, or add an API key, to choose a model here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button("Open Settings") {
                    onOpenSettings()
                }
                .font(.caption.weight(.semibold))
            } else {
                TextField("Search models", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleProfiles) { profile in
                            let models = models(for: profile)
                            if !models.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                    if let caption = availabilityCaption(for: profile) {
                                        Text(caption)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    ForEach(models) { model in
                                        Button {
                                            onSelect(profile.id, model.modelName)
                                        } label: {
                                            HStack(alignment: .firstTextBaseline) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(model.title)
                                                        .foregroundStyle(.primary)
                                                    if !model.parameterSummary.isEmpty {
                                                        Text(model.parameterSummary)
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                Spacer()
                                                if profile.id == conversation.profileID, model.modelName == conversation.modelName {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.weight(.semibold))
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(
                                                profile.id == conversation.profileID && model.modelName == conversation.modelName
                                                    ? OtohaChatTheme.chipFill
                                                    : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button("Copy model") {
                                                Clipboard.copy(model.modelName)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: style == .sheet ? .infinity : 240)
            }

            if let profile, let model = profile.catalogModel(named: conversation.modelName),
               conversation.reasoning.showsReasoningControls(for: model, kind: profile.kind) {
                Divider()
                Text("Reasoning")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Picker(
                    "Reasoning",
                    selection: reasoningBinding(model: model, kind: profile.kind)
                ) {
                    ForEach(reasoningValues(model), id: \.self) { value in
                        Text(value.replacingOccurrences(of: "_", with: " ").capitalized)
                            .tag(value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
        .padding(14)
        #if os(macOS)
        .frame(width: 300)
        #endif
        .frame(
            maxWidth: .infinity,
            maxHeight: style == .sheet ? .infinity : nil,
            alignment: .topLeading
        )
    }

    private var profile: ProviderProfile? {
        store.settings.profiles.first(where: { $0.id == conversation.profileID })
    }

    private var visibleProfiles: [ProviderProfile] {
        store.pickerProfiles(including: conversation.profileID)
    }

    private func models(for profile: ProviderProfile) -> [CatalogModelChoice] {
        var models = profile.pickerModels
        if models.isEmpty, let fallback = profile.effectiveModelID, !fallback.isEmpty {
            models = [
                CatalogModelChoice(
                    modelName: fallback,
                    displayName: profile.displayName,
                    source: "profile"
                )
            ]
        }
        if profile.id == conversation.profileID,
           !models.contains(where: { $0.modelName == conversation.modelName }),
           !conversation.modelName.isEmpty
        {
            models.insert(
                CatalogModelChoice(modelName: conversation.modelName, source: "conversation"),
                at: 0
            )
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return models }
        return models.filter {
            $0.modelName.localizedCaseInsensitiveContains(trimmed)
                || ($0.displayName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private func availabilityCaption(for profile: ProviderProfile) -> String? {
        switch profile.kind {
        case .applePCC where !store.pccStatus.isAvailable:
            store.pccStatus.title
        case .appleOnDevice where !store.onDeviceStatus.isAvailable:
            store.onDeviceStatus.title
        default:
            nil
        }
    }

    private func reasoningValues(_ model: CatalogModelChoice) -> [String] {
        let kind = profile?.kind ?? .anthropic
        return conversation.reasoning.pickerReasoningValues(for: model, kind: kind)
    }

    private func reasoningBinding(model: CatalogModelChoice, kind: ProviderKind) -> Binding<String> {
        Binding(
            get: { conversation.reasoning.selectedReasoningValue(for: model, kind: kind) },
            set: { onReasoning($0) }
        )
    }
}
