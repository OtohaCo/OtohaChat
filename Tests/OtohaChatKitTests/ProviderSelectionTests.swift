import AgentCatalog
import AgentModels
import OtohaChatKit
import Foundation
import Testing

struct ProviderSelectionTests {
    @Test func closedOrUnkeyedHTTPProvidersAreNotReady() {
        var openai = ProviderProfile(kind: .openaiResponses, isEnabled: false)
        let none = ProviderSelection(hasAPIKey: false, pccAvailable: false, onDeviceAvailable: false)
        #expect(!openai.isReady(for: none))

        openai.isEnabled = true
        #expect(!openai.isReady(for: none))

        let keyed = ProviderSelection(hasAPIKey: true, pccAvailable: false, onDeviceAvailable: false)
        #expect(openai.isReady(for: keyed))
    }

    @Test func appleNeedsAvailabilityNotAnAPIKey() {
        let pcc = ProviderProfile(kind: .applePCC, isEnabled: true)
        let off = ProviderSelection(hasAPIKey: false, pccAvailable: false, onDeviceAvailable: true)
        #expect(!pcc.isReady(for: off))
        let on = ProviderSelection(hasAPIKey: false, pccAvailable: true, onDeviceAvailable: false)
        #expect(pcc.isReady(for: on))
    }

    @Test func noisyOpenAICatalogEntriesStayOutOfTheChatPicker() {
        #expect(CatalogDisplayPolicy.isOfferedInChatPicker(kind: .openaiResponses, modelName: "gpt-4.1"))
        #expect(!CatalogDisplayPolicy.isOfferedInChatPicker(kind: .openaiResponses, modelName: "whisper-1"))
        #expect(!CatalogDisplayPolicy.isOfferedInChatPicker(kind: .openaiResponses, modelName: "text-embedding-3-large"))
        #expect(CatalogDisplayPolicy.isOfferedInChatPicker(kind: .anthropic, modelName: "claude-sonnet-4-5"))
    }

    @Test func overlayFillsUnknownOpenAIEffortWithoutInventingUnsupportedFacts() {
        let unknown = CatalogModelChoice(modelName: "gpt-4.1", source: "upstream_api")
        let merged = CatalogCapabilityOverlay.merge(kind: .openaiResponses, model: unknown)
        #expect(merged.hasAdjustableReasoning)
        #expect(merged.usedHostManifest)
        #expect(merged.effortValues?.contains("xhigh") == true)

        var reported = unknown
        reported.reasoning = ModelCatalogSupport.unsupported.rawValue
        reported.configurableReasoning = ModelCatalogSupport.unsupported.rawValue
        let leftAlone = CatalogCapabilityOverlay.merge(kind: .openaiResponses, model: reported)
        #expect(!leftAlone.hasAdjustableReasoning)
        #expect(!leftAlone.usedHostManifest)
    }

    @Test func catalogEntryMappingKeepsAnthropicReasoningControls() throws {
        let scope = try ModelServiceScope(
            provider: "anthropic",
            serviceInstanceID: "test",
            endpointScope: "https://api.anthropic.com/v1",
            apiDialect: "anthropic-models"
        )
        let entry = ModelCatalogEntry(
            model: .init(provider: "anthropic", name: "claude-future"),
            deploymentID: "claude-future",
            serviceScope: scope,
            displayName: "Claude Future",
            capabilities: .init(
                tools: .supported,
                reasoning: .supported,
                configurableReasoning: .supported
            ),
            reasoningControls: [
                .init(
                    parameter: "output_config.effort",
                    kind: .effort,
                    support: .supported,
                    allowedValues: ["low", "high"],
                    executability: .executable
                ),
            ],
            maximumInputTokens: 200_000,
            maximumOutputTokens: 64_000,
            sources: [.init(kind: .upstreamAPI, reference: "GET /v1/models")]
        )
        let choice = CatalogModelChoice(entry: entry)
        #expect(choice.displayName == "Claude Future")
        #expect(choice.effortValues == ["low", "high"])
        #expect(choice.maximumInputTokens == 200_000)
        #expect(choice.hasAdjustableReasoning)
        #expect(choice.parameterSummary.contains("Reasoning"))
    }

    @Test func legacyCatalogJSONStillDecodes() throws {
        let data = Data(#"{"modelName":"gpt-test","displayName":null,"source":"manual"}"#.utf8)
        let choice = try JSONDecoder().decode(CatalogModelChoice.self, from: data)
        #expect(choice.modelName == "gpt-test")
        #expect(choice.reasoningSupport == .unknown)
        #expect(!choice.hasAdjustableReasoning)
    }

    @Test func catalogReasoningPickerWritesProviderNativeValues() {
        let model = CatalogCapabilityOverlay.merge(
            kind: .openaiResponses,
            model: CatalogModelChoice(modelName: "gpt-4.1", source: "upstream_api")
        )
        var reasoning = ReasoningConfiguration()
        reasoning.applyCatalogReasoning("xhigh", model: model, kind: .openaiResponses)
        #expect(reasoning.openaiEffort == .effort("xhigh"))
        #expect(reasoning.selectedReasoningValue(for: model, kind: .openaiResponses) == "xhigh")
        reasoning.applyCatalogReasoning("none", model: model, kind: .openaiResponses)
        #expect(reasoning.openaiEffort == .disabled)
    }

    @Test func anthropicEffortEnablesAdaptiveThinking() {
        var model = CatalogModelChoice(modelName: "claude-opus-4-6", source: "upstream_api")
        model.effortValues = ["low", "medium", "high"]
        model.configurableReasoning = ModelCatalogSupport.supported.rawValue
        var reasoning = ReasoningConfiguration()
        reasoning.applyCatalogReasoning("medium", model: model, kind: .anthropic)
        #expect(reasoning.anthropicEffort == "medium")
        #expect(reasoning.anthropicThinking == .thinkingAdaptive)
        reasoning.setIntensity(.off, for: .anthropic)
        #expect(reasoning.anthropicThinking == .thinkingDisabled)
    }

    @Test @MainActor func readyProfilesIgnoreClosedProviders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let locations = AppFileLocations(root: root)
        try FileManager.default.createDirectory(at: locations.sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.notes, withIntermediateDirectories: true)
        let store = try ChatStore(
            locations: locations,
            secrets: MemorySecretStore(),
            factory: ProviderFactory(
                onDeviceStatus: { .unsupportedSystem("test") },
                pccStatus: { .unsupportedSystem("test") }
            )
        )
        store.pccStatus = .unsupportedSystem("test")
        store.onDeviceStatus = .unsupportedSystem("test")
        #expect(store.readyProfiles().isEmpty)

        let openai = try #require(store.settings.profiles.first(where: { $0.kind == .openaiResponses }))
        try store.secrets.save(account: openai.credentialAccount, secret: "test-key-not-real")
        var document = store.settings
        let index = try #require(document.profiles.firstIndex(where: { $0.id == openai.id }))
        document.profiles[index].isEnabled = true
        try store.saveSettings(document)
        #expect(store.readyProfiles().contains(where: { $0.id == openai.id }))

        document.profiles[index].isEnabled = false
        try store.saveSettings(document)
        #expect(!store.readyProfiles().contains(where: { $0.id == openai.id }))
        try? FileManager.default.removeItem(at: root)
    }

    @Test @MainActor func newChatUsesEnabledAppleWhenTheRuntimeIsUnavailable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let locations = AppFileLocations(root: root)
        try FileManager.default.createDirectory(at: locations.sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.notes, withIntermediateDirectories: true)
        let store = try ChatStore(
            locations: locations,
            secrets: MemorySecretStore(),
            factory: ProviderFactory(
                onDeviceStatus: { .modelUnavailable("test") },
                pccStatus: { .modelUnavailable("test") }
            )
        )
        store.pccStatus = .modelUnavailable("Apple Private Cloud Compute is not ready on this system.")
        store.onDeviceStatus = .modelUnavailable("The on-device Apple model is unavailable.")
        #expect(store.readyProfiles().isEmpty)
        let id = try #require(store.createConversation())
        let conversation = try #require(store.conversation(id))
        #expect(conversation.profileID == store.settings.profiles.first { $0.kind == .applePCC }?.id)
        let picker = store.pickerProfiles(including: conversation.profileID)
        #expect(picker.contains(where: { $0.kind == .applePCC }))
        #expect(picker.contains(where: { $0.kind == .appleOnDevice }))
        try? FileManager.default.removeItem(at: root)
    }
}
