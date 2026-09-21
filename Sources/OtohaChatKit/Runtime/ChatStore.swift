import AgentCore
import AgentModels
import AgentTools
import Foundation

public struct ChatSessionSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var profileID: UUID
    public var modelName: String
    public var reasoning: ReasoningConfiguration
    public var snapshot: ConversationSnapshot
    public var inputError: String?
    public var configurationAppliesNext: Bool
    public var enabledSkillNames: [String]
    public var availabilityMessage: String?

    public init(
        id: UUID,
        title: String,
        profileID: UUID,
        modelName: String,
        reasoning: ReasoningConfiguration,
        snapshot: ConversationSnapshot,
        inputError: String? = nil,
        configurationAppliesNext: Bool = false,
        enabledSkillNames: [String] = [],
        availabilityMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.profileID = profileID
        self.modelName = modelName
        self.reasoning = reasoning
        self.snapshot = snapshot
        self.inputError = inputError
        self.configurationAppliesNext = configurationAppliesNext
        self.enabledSkillNames = enabledSkillNames
        self.availabilityMessage = availabilityMessage
    }
}

public enum PCCQualification {
    public static let status = "BLOCKED_CONFIGURATION"
    public static let note = """
    SwiftAgent 1.0.0-rc.3 treats Apple Private Cloud Compute as experimental. \
    This app has not completed the signed live core loop \
    (PCC → Agent → Session → Run → Calculator → Core executor → second PCC turn → terminal → drain). \
    PCC text availability is not the same as a passing tool-loop or durable restart.
    """
}

@MainActor
public final class ChatStore: ObservableObject {
    @Published public private(set) var conversations: [ChatSessionSummary] = []
    @Published public var selectedID: UUID?
    @Published public private(set) var settings: ProviderSettingsDocument
    @Published public private(set) var skills: [SkillMetadata] = []
    @Published public var workspaceURL: URL?
    @Published public var pccStatus: AppleRuntimeStatus
    @Published public var onDeviceStatus: AppleRuntimeStatus
    @Published public var banner: String?
    @Published public var pendingMutation: MutationApprovalRequest?
    @Published public var fixtureEnabled: Bool
    @Published public var shouldOpenSettings = false
    @Published public private(set) var refreshingCatalogIDs: Set<UUID> = []

    public let secrets: any SecretStore
    public let locations: AppFileLocations
    public let factory: ProviderFactory
    public let catalog: CatalogService
    public let mutationApprover: PromptingMutationApprover

    private let transcripts: TranscriptStore
    private let settingsStore: SettingsStore
    private let notesStore: FileNotesStore
    private let workspaceGate: WorkspaceGate
    private let scheduler = ToolScheduler()
    private var lives: [UUID: LiveSession] = [:]
    private var observers: [UUID: Task<Void, Never>] = [:]
    private var mutationObserver: Task<Void, Never>?
    private var didBootstrap = false

    public static func makeDefault() -> ChatStore {
        let locations = (try? AppFileLocations.default())
            ?? AppFileLocations(
                root: FileManager.default.temporaryDirectory.appendingPathComponent("OtohaChat", isDirectory: true)
            )
        if let store = try? ChatStore(locations: locations, secrets: KeychainSecretStore()) {
            return store
        }
        let fallback = AppFileLocations(
            root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        return try! ChatStore(locations: fallback, secrets: MemorySecretStore())
    }

    public init(
        locations: AppFileLocations,
        secrets: any SecretStore,
        factory: ProviderFactory = ProviderFactory(),
        fixtureEnabled: Bool = FixtureLaunchToken.isEnabled()
    ) throws {
        self.locations = locations
        self.secrets = secrets
        self.factory = factory
        self.fixtureEnabled = fixtureEnabled
        catalog = CatalogService()
        mutationApprover = PromptingMutationApprover()
        transcripts = TranscriptStore(locations: locations)
        settingsStore = SettingsStore(locations: locations)
        notesStore = try FileNotesStore(directory: locations.notes)
        workspaceGate = WorkspaceGate()
        settings = (try? settingsStore.load()) ?? ProviderSettingsDocument()
        pccStatus = AppleRuntimeProbe.pccStatus()
        onDeviceStatus = AppleRuntimeProbe.onDeviceStatus()
        banner = nil
    }

    public func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        refreshAppleStatus()
        try? restoreAll()
        if conversations.isEmpty {
            _ = createConversation()
        }
        if selectedID == nil {
            selectedID = conversations.first?.id
        }
        refreshSkills()
        refreshReadyCatalogsIfNeeded()
    }

    public func refreshAppleStatus() {
        pccStatus = AppleRuntimeProbe.pccStatus()
        onDeviceStatus = AppleRuntimeProbe.onDeviceStatus()
    }

    @discardableResult
    public func createConversation(profileID: UUID? = nil) -> UUID? {
        guard let profile = resolvedProfile(profileID) else {
            banner = "Turn on a provider in Settings before chatting."
            shouldOpenSettings = true
            return nil
        }
        banner = nil
        let id = UUID()
        let modelName = profile.effectiveModelID ?? defaultModelName(for: profile)
        let summary = ChatSessionSummary(
            id: id,
            title: "New chat",
            profileID: profile.id,
            modelName: modelName,
            reasoning: profile.reasoning.clamped(
                to: profile.catalogModel(named: modelName),
                kind: profile.kind
            ),
            snapshot: ConversationSnapshot(conversationID: id),
            availabilityMessage: availabilityNote(for: profile)
        )
        conversations.insert(summary, at: 0)
        selectedID = id
        persist(id)
        return id
    }

    public func createFixtureConversation() -> UUID? {
        let id = UUID()
        do {
            let controller = try makeFixtureConversationController(conversationID: id, pacing: .visible)
            lives[id] = LiveSession(controller: controller, lastPrepared: nil, modelName: "fixture-assistant")
            conversations.insert(
                ChatSessionSummary(
                    id: id,
                    title: "Fixture chat",
                    profileID: settings.profiles.first?.id ?? id,
                    modelName: "fixture-assistant",
                    reasoning: .init(),
                    snapshot: ConversationSnapshot(conversationID: id),
                    availabilityMessage: "Fixture mode is explicit. Ordinary chats never fall back to this provider."
                ),
                at: 0
            )
            selectedID = id
            observe(id)
            return id
        } catch {
            banner = SecretRedactor.redact(error.localizedDescription)
            return nil
        }
    }

    public func conversation(_ id: UUID?) -> ChatSessionSummary? {
        guard let id else { return nil }
        return conversations.first(where: { $0.id == id })
    }

    public func send(_ text: String, conversationID: UUID) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let visible = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visible.isEmpty else {
            conversations[index].inputError = "Enter a message before sending."
            return
        }
        if conversations[index].snapshot.isBusy {
            conversations[index].inputError = "Wait for the current reply to finish before sending again."
            return
        }

        let committedItems = conversations[index].snapshot.items
        let rollback = conversations[index].snapshot
        applyOptimisticTurn(text: visible, at: index)

        do {
            var live = try await ensureLive(conversationID)
            if live.lastPrepared == nil, conversations[index].modelName == "fixture-assistant" {
                try await live.controller.send(ConversationStartRequest(text: visible, displayText: visible))
                conversations[index].inputError = nil
                return
            }
            let profile = try profile(conversations[index].profileID)
            let apiKey = try secrets.load(account: profile.credentialAccount)
            let prepared = try factory.prepare(
                profile: withRunConfig(profile, conversations[index]),
                apiKey: apiKey,
                modelOverride: conversations[index].modelName
            )
            let plan = HandoffPolicy.plan(from: live.lastPrepared, to: prepared)
            if case .rejected(let reason) = plan {
                conversations[index].snapshot = rollback
                conversations[index].inputError = reason
                return
            }
            if live.lastPrepared == nil {
                await live.controller.restoreDisplayItems(committedItems)
            }
            let binding = try prepared.makeBinding(projector: HandoffPolicy.projector(for: plan))
            let revision = await live.controller.canonicalSnapshot().revision
            let snapshots = activatedSnapshots(for: conversations[index], text: visible)
            let payload = SkillPromptBuilder.envelope(userText: visible, snapshots: snapshots)
            try await live.controller.send(
                ConversationStartRequest(
                    text: payload,
                    displayText: visible,
                    binding: binding,
                    expectedRevision: revision,
                    handoffWarning: plan.warning
                )
            )
            live.lastPrepared = prepared
            lives[conversationID] = live
            conversations[index].inputError = nil
            conversations[index].configurationAppliesNext = false
            if conversations[index].title == "New chat" {
                conversations[index].title = String(visible.prefix(42))
            }
        } catch ConversationControllerError.runInProgress {
            conversations[index].snapshot = rollback
            conversations[index].inputError = "Wait for the current reply to finish before sending again."
        } catch let error as AgentModelBindingError {
            conversations[index].snapshot = rollback
            conversations[index].inputError = handoffError(error)
        } catch let error as ProviderFactoryError {
            conversations[index].snapshot = rollback
            conversations[index].inputError = error.errorDescription ?? error.localizedDescription
            if case .missingAPIKey = error {
                shouldOpenSettings = true
            }
        } catch {
            conversations[index].snapshot = rollback
            conversations[index].inputError = SecretRedactor.redact(error.localizedDescription)
        }
    }

    private func applyOptimisticTurn(text: String, at index: Int) {
        var snapshot = conversations[index].snapshot
        snapshot.phase = .starting
        snapshot.terminal = nil
        snapshot.generation &+= 1
        snapshot.items.append(.user(.init(text: text)))
        let turn = DisplayAssistantTurn()
        snapshot.currentAssistantTurnID = turn.id
        snapshot.items.append(.assistant(turn))
        conversations[index].snapshot = snapshot
        conversations[index].inputError = nil
        if conversations[index].title == "New chat" {
            conversations[index].title = String(text.prefix(42))
        }
    }

    public func stop(conversationID: UUID) async {
        await lives[conversationID]?.controller.stop()
    }

    public func rename(_ id: UUID, title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = title
        persist(id)
    }

    public func delete(_ id: UUID) async {
        if conversations.first(where: { $0.id == id })?.snapshot.isBusy == true {
            await lives[id]?.controller.stop()
        }
        observers[id]?.cancel()
        observers[id] = nil
        lives[id] = nil
        conversations.removeAll { $0.id == id }
        try? transcripts.delete(id: id)
        if selectedID == id {
            selectedID = conversations.first?.id
        }
    }

    public func updateRunConfiguration(
        conversationID: UUID,
        profileID: UUID,
        modelName: String,
        reasoning: ReasoningConfiguration
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let busy = conversations[index].snapshot.isBusy
        conversations[index].profileID = profileID
        conversations[index].modelName = modelName
        conversations[index].reasoning = clampedReasoning(
            reasoning,
            profileID: profileID,
            modelName: modelName
        )
        conversations[index].configurationAppliesNext = busy
        persist(conversationID)
    }

    public func shouldConfirmModelSwitch(
        conversationID: UUID,
        profileID: UUID,
        modelName: String
    ) -> Bool {
        guard let conversation = conversation(conversationID) else { return false }
        let hasHistory = conversation.snapshot.items.contains { item in
            if case .user = item { return true }
            return false
        }
        return hasHistory && (conversation.profileID != profileID || conversation.modelName != modelName)
    }

    public func applyModelSelection(
        conversationID: UUID,
        profileID: UUID,
        modelName: String,
        reasoning: ReasoningConfiguration,
        startNewChat: Bool
    ) {
        if startNewChat {
            guard let newID = createConversation(profileID: profileID) else { return }
            updateRunConfiguration(
                conversationID: newID,
                profileID: profileID,
                modelName: modelName,
                reasoning: reasoning
            )
            return
        }
        updateRunConfiguration(
            conversationID: conversationID,
            profileID: profileID,
            modelName: modelName,
            reasoning: reasoning
        )
    }

    public func saveSettings(_ document: ProviderSettingsDocument) throws {
        settings = document
        try settingsStore.save(document)
    }

    public func setAPIKey(profileID: UUID, secret: String) throws {
        try secrets.save(account: CredentialAccount.apiKey(profileID: profileID), secret: secret)
        if let index = settings.profiles.firstIndex(where: { $0.id == profileID }) {
            settings.profiles[index].isEnabled = true
            try? settingsStore.save(settings)
        }
        objectWillChange.send()
        Task { await refreshCatalog(profileID: profileID) }
    }

    public func deleteAPIKey(profileID: UUID) throws {
        try secrets.delete(account: CredentialAccount.apiKey(profileID: profileID))
        objectWillChange.send()
    }

    public func hasAPIKey(profileID: UUID) -> Bool {
        (try? secrets.load(account: CredentialAccount.apiKey(profileID: profileID)))?.isEmpty == false
    }

    public func refreshCatalog(profileID: UUID) async {
        guard var profile = settings.profiles.first(where: { $0.id == profileID }) else { return }
        refreshingCatalogIDs.insert(profileID)
        defer { refreshingCatalogIDs.remove(profileID) }
        let key = try? secrets.load(account: profile.credentialAccount)
        let probe = ConnectivityProbe(factory: factory, catalog: catalog)
        let (updated, _) = await probe.checkCatalog(profile: profile, apiKey: key)
        profile = updated
        if let index = settings.profiles.firstIndex(where: { $0.id == profileID }) {
            settings.profiles[index] = profile
            try? settingsStore.save(settings)
        }
    }

    public func selectionContext(hasAPIKeyFor profileID: UUID) -> ProviderSelection {
        ProviderSelection(
            hasAPIKey: hasAPIKey(profileID: profileID),
            pccAvailable: pccStatus.isAvailable,
            onDeviceAvailable: onDeviceStatus.isAvailable
        )
    }

    public func readyProfiles() -> [ProviderProfile] {
        settings.profiles.filter { $0.isReady(for: selectionContext(hasAPIKeyFor: $0.id)) }
    }

    public func pickerProfiles(including conversationProfileID: UUID? = nil) -> [ProviderProfile] {
        settings.profiles.filter { profile in
            if profile.id == conversationProfileID { return true }
            guard profile.isEnabled else { return false }
            if profile.isReady(for: selectionContext(hasAPIKeyFor: profile.id)) { return true }
            return profile.kind == .applePCC || profile.kind == .appleOnDevice
        }
    }

    public func setProviderEnabled(profileID: UUID, enabled: Bool) {
        guard let index = settings.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        settings.profiles[index].isEnabled = enabled
        try? settingsStore.save(settings)
        if enabled {
            Task { await refreshCatalog(profileID: profileID) }
        }
    }

    public func refreshReadyCatalogsIfNeeded() {
        for profile in settings.profiles where profile.isEnabled {
            let canDiscover = !profile.kind.requiresAPIKey || hasAPIKey(profileID: profile.id)
            guard canDiscover, profile.catalogModels.isEmpty else { continue }
            let id = profile.id
            Task { await refreshCatalog(profileID: id) }
        }
    }

    public func setWorkspace(_ url: URL?) {
        workspaceURL = url
        workspaceGate.set(url)
        refreshSkills()
    }

    public func refreshSkills() {
        var discovered: [SkillMetadata] = []
        if let workspaceURL {
            discovered.append(contentsOf: SkillDiscovery.discover(root: workspaceURL, originLabel: "Workspace"))
        }
        skills = dedupe(discovered)
    }

    public func setEnabledSkills(_ names: [String], conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].enabledSkillNames = names
        persist(conversationID)
    }

    public func respondToMutation(_ allowed: Bool) {
        pendingMutation = nil
        Task { await mutationApprover.respond(allowed) }
    }

    public func preferredProfile() -> ProviderProfile? {
        let ready = readyProfiles()
        if let pcc = ready.first(where: { $0.kind == .applePCC }) { return pcc }
        if let onDevice = ready.first(where: { $0.kind == .appleOnDevice }) { return onDevice }
        if let id = settings.defaultProfileID, let profile = ready.first(where: { $0.id == id }) {
            return profile
        }
        if let ready = ready.first { return ready }
        let enabled = settings.profiles.filter(\.isEnabled)
        if let pcc = enabled.first(where: { $0.kind == .applePCC }) { return pcc }
        if let onDevice = enabled.first(where: { $0.kind == .appleOnDevice }) { return onDevice }
        return enabled.first
    }

    private func restoreAll() throws {
        let saved = try transcripts.list()
        for transcript in saved {
            do {
                let profile = try profile(transcript.profileID)
                let live = try makeLiveSession(
                    id: transcript.conversationID,
                    profile: profile,
                    modelName: transcript.modelName,
                    reasoning: transcript.reasoning,
                    restoreJournal: true
                )
                lives[transcript.conversationID] = live
                let items = transcript.items.map(\.conversationItem)
                Task { await live.controller.restoreDisplayItems(items) }
                conversations.append(
                    ChatSessionSummary(
                        id: transcript.conversationID,
                        title: transcript.title,
                        profileID: transcript.profileID,
                        modelName: transcript.modelName,
                        reasoning: transcript.reasoning,
                        snapshot: ConversationSnapshot(conversationID: transcript.conversationID, items: items),
                        enabledSkillNames: transcript.enabledSkillNames,
                        availabilityMessage: availabilityNote(for: profile)
                    )
                )
                observe(transcript.conversationID)
            } catch {
                conversations.append(
                    ChatSessionSummary(
                        id: transcript.conversationID,
                        title: transcript.title,
                        profileID: transcript.profileID,
                        modelName: transcript.modelName,
                        reasoning: transcript.reasoning,
                        snapshot: ConversationSnapshot(conversationID: transcript.conversationID),
                        inputError: "This session could not be restored: \(SecretRedactor.redact(error.localizedDescription))"
                    )
                )
            }
        }
    }

    private func ensureLive(_ id: UUID) async throws -> LiveSession {
        if let live = lives[id] { return live }
        guard let conversation = conversations.first(where: { $0.id == id }) else {
            throw ConversationControllerError.emptyInput
        }
        let profile = try profile(conversation.profileID)
        let live = try makeLiveSession(
            id: id,
            profile: profile,
            modelName: conversation.modelName,
            reasoning: conversation.reasoning,
            restoreJournal: true
        )
        lives[id] = live
        observe(id)
        return live
    }

    private func resolvedProfile(_ id: UUID?) -> ProviderProfile? {
        if let id, let match = settings.profiles.first(where: { $0.id == id }) {
            return match
        }
        return preferredProfile()
    }

    private func makeLiveSession(
        id: UUID,
        profile: ProviderProfile,
        modelName: String,
        reasoning: ReasoningConfiguration,
        restoreJournal: Bool
    ) throws -> LiveSession {
        let directory = locations.sessionDirectory(id: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = try AgentJournal(persistenceURL: locations.journalURL(id: id))
        let tools = try makeTools()
        let prepared: PreparedProvider?
        let provider: any ModelProvider
        let model: ModelID
        let apiKey = try secrets.load(account: profile.credentialAccount)
        let value = try factory.prepare(
            profile: withRunConfig(profile, modelName: modelName, reasoning: reasoning),
            apiKey: apiKey,
            modelOverride: modelName
        )
        prepared = value
        provider = value.provider
        model = value.model
        let agent = try Agent(
            model: model,
            provider: provider,
            tools: tools,
            configuration: AgentConfiguration(
                instructions: AppInstructions.base,
                maxModelTurns: 12,
                maxToolCalls: 20,
                runTimeout: .seconds(180),
                scheduler: scheduler
            )
        )
        let session = try agent.makeSession(id: id, journal: journal)
        return LiveSession(
            controller: ConversationController(
                conversationID: id,
                session: AgentConversationSessionHandle(session: session)
            ),
            lastPrepared: prepared,
            modelName: modelName
        )
    }

    private func makeTools() throws -> [any AgentTool] {
        [
            try CalculatorTool(),
            try DateTimeTool(),
            try WorkspaceReadTool(rootProvider: { [workspaceGate] in workspaceGate.current() }),
            try AppNotesReadTool(store: notesStore),
            try AppNotesTool(store: notesStore, approver: mutationApprover),
        ]
    }

    private func observe(_ id: UUID) {
        guard let controller = lives[id]?.controller else { return }
        observers[id]?.cancel()
        observers[id] = Task { [weak self] in
            for await snapshot in controller.snapshots {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.apply(snapshot, conversationID: id)
                }
            }
        }
        if mutationObserver == nil {
            mutationObserver = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    let pending = await self?.mutationApprover.pending
                    await MainActor.run {
                        self?.pendingMutation = pending
                    }
                }
            }
        }
    }

    private func apply(_ snapshot: ConversationSnapshot, conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].snapshot = snapshot
        if !snapshot.isBusy {
            persist(conversationID)
        }
    }

    private func persist(_ id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        let transcript = ChatTranscript(
            conversationID: id,
            title: conversation.title,
            profileID: conversation.profileID,
            modelName: conversation.modelName,
            reasoning: conversation.reasoning,
            items: conversation.snapshot.items.map(PersistedTranscriptItem.init),
            enabledSkillNames: conversation.enabledSkillNames,
            workspacePath: workspaceURL?.path
        )
        try? transcripts.save(transcript)
    }

    private func profile(_ id: UUID) throws -> ProviderProfile {
        guard let profile = settings.profiles.first(where: { $0.id == id }) else {
            throw ProviderFactoryError.missingModelID
        }
        return profile
    }

    private func clampedReasoning(
        _ reasoning: ReasoningConfiguration,
        profileID: UUID,
        modelName: String
    ) -> ReasoningConfiguration {
        guard let profile = settings.profiles.first(where: { $0.id == profileID }) else {
            return reasoning
        }
        return reasoning.clamped(to: profile.catalogModel(named: modelName), kind: profile.kind)
    }

    private func withRunConfig(_ profile: ProviderProfile, _ conversation: ChatSessionSummary) -> ProviderProfile {
        withRunConfig(profile, modelName: conversation.modelName, reasoning: conversation.reasoning)
    }

    private func withRunConfig(
        _ profile: ProviderProfile,
        modelName: String,
        reasoning: ReasoningConfiguration
    ) -> ProviderProfile {
        var copy = profile
        copy.selectedModelID = modelName
        copy.reasoning = reasoning
        return copy
    }

    private func defaultModelName(for profile: ProviderProfile) -> String {
        if let selected = profile.effectiveModelID { return selected }
        if let first = profile.pickerModels.first { return first.modelName }
        switch profile.kind {
        case .applePCC: return AppleFoundationProviderName.pcc
        case .appleOnDevice: return AppleFoundationProviderName.onDevice
        default: return profile.manualModelID.isEmpty ? "model" : profile.manualModelID
        }
    }

    private func availabilityNote(for profile: ProviderProfile) -> String? {
        switch profile.kind {
        case .applePCC:
            if pccStatus.isAvailable { return nil }
            return pccStatus.detail
        case .appleOnDevice:
            if onDeviceStatus.isAvailable { return nil }
            return onDeviceStatus.detail
        default:
            return nil
        }
    }

    private func activatedSnapshots(for conversation: ChatSessionSummary, text: String) -> [SkillSnapshot] {
        var names = Set(conversation.enabledSkillNames)
        if let slash = SkillPromptBuilder.detectSlashSkill(in: text, available: skills) {
            names.insert(slash.0.name)
        }
        return skills.filter { names.contains($0.name) }.map {
            let refs = requestedReferences(in: $0)
            return SkillDiscovery.loadSnapshot($0, requestedReferences: refs)
        }
    }

    private func requestedReferences(in skill: SkillMetadata) -> [String] {
        ["references/overview.md", "references/README.md"].filter {
            FileManager.default.fileExists(atPath: skill.sourceDirectory.appendingPathComponent($0).path)
        }
    }

    private func dedupe(_ skills: [SkillMetadata]) -> [SkillMetadata] {
        var seen: [String: SkillMetadata] = [:]
        var result: [SkillMetadata] = []
        for skill in skills {
            if var existing = seen[skill.name] {
                existing.issues.append(.init(
                    code: .nameConflict,
                    message: "Name \(skill.name) also exists at \(skill.originLabel)."
                ))
                seen[skill.name] = existing
                if let index = result.firstIndex(where: { $0.name == skill.name }) {
                    result[index] = existing
                }
            } else {
                seen[skill.name] = skill
                result.append(skill)
            }
        }
        return result
    }

    private func handoffError(_ error: AgentModelBindingError) -> String {
        switch error {
        case .incompatibleContinuation:
            return "This history cannot continue on the selected model without forging provider continuation. The original session was kept."
        case .staleConversationRevision:
            return "The conversation changed before the new run started. Send again."
        case .providerMismatch:
            return "The selected model does not match the provider identity."
        case .contextBudgetExceeded(let estimated, let available):
            return "This history is too large for the selected model (\(estimated) > \(available) tokens). The original session was kept."
        default:
            return SecretRedactor.redact(String(describing: error))
        }
    }
}

private struct LiveSession {
    var controller: ConversationController
    var lastPrepared: PreparedProvider?
    var modelName: String
}

private enum AppleFoundationProviderName {
    static let pcc = "private-cloud-compute"
    static let onDevice = "on-device"
}
