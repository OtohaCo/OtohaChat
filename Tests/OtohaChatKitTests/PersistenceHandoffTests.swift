import OtohaChatKit
import Foundation
import Testing

struct PersistenceAndHandoffTests {
    @Test func transcriptsRoundTripWithoutSecrets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let locations = AppFileLocations(root: root)
        try FileManager.default.createDirectory(at: locations.sessions, withIntermediateDirectories: true)
        let store = TranscriptStore(locations: locations)
        let id = UUID()
        let transcript = ChatTranscript(
            conversationID: id,
            title: "Saved",
            profileID: UUID(),
            modelName: "gpt-test",
            reasoning: .init(openaiEffort: .effort("high")),
            items: [.user(id: UUID(), text: "hello")]
        )
        try store.save(transcript)
        let loaded = try store.load(id: id)
        #expect(loaded.title == "Saved")
        let encoded = try JSONEncoder().encode(loaded)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.lowercased().contains("sk-"))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func handoffAcrossProvidersIsSemanticNotSilent() throws {
        let openai = ProviderProfile(kind: .openaiResponses, serviceInstanceID: "openai-1", manualModelID: "gpt-test")
        let anthropic = ProviderProfile(kind: .anthropic, serviceInstanceID: "anthropic-1", manualModelID: "claude-test")
        let factory = ProviderFactory()
        let first = try factory.prepare(profile: openai, apiKey: "test-key-not-real")
        let second = try factory.prepare(profile: anthropic, apiKey: "test-key-not-real")
        let plan = HandoffPolicy.plan(from: first, to: second)
        guard case .semantic(let warning) = plan else {
            Issue.record("expected semantic handoff")
            return
        }
        #expect(warning.contains("not a lossless transfer"))
    }

    @Test func settingsDoNotContainAPIKeys() throws {
        var document = ProviderSettingsDocument()
        document.profiles[0].notes = "no secrets"
        let data = try JSONEncoder().encode(document)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("apiKey"))
        #expect(!text.contains("sk-"))
    }
}

struct PCCStatusTests {
    @Test func pccNeverClaimsAvailabilityFromEntitlementFileAlone() {
        let status = AppleRuntimeProbe.pccStatus(pccBuildEnabled: false)
        #expect(!status.isAvailable)
        if case .available = status {
            Issue.record("Unsigned tests must not report PCC as available.")
        }
        #expect(PCCQualification.status == "BLOCKED_CONFIGURATION")
    }

    @Test @MainActor func availablePCCDoesNotPaintChatAsBroken() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let locations = AppFileLocations(root: root)
        try FileManager.default.createDirectory(at: locations.sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.notes, withIntermediateDirectories: true)
        let store = try ChatStore(
            locations: locations,
            secrets: MemorySecretStore(),
            factory: ProviderFactory(
                onDeviceStatus: { .available },
                pccStatus: { .available }
            )
        )
        store.pccStatus = .available
        store.onDeviceStatus = .available
        #expect(store.banner != PCCQualification.note)
        let id = try #require(store.createConversation())
        #expect(store.conversation(id)?.availabilityMessage == nil)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func iosProbeDoesNotUseTheAppTargetCompileFlag() {
        // The TestFlight failure was this scheme-missing message, which the kit
        // emitted because OTOHACHAT_PCC never reached the SPM target.
        let blocked = AppleRuntimeProbe.pccStatus(pccBuildEnabled: false)
        #if os(iOS)
        if case .entitlementMissing(let detail) = blocked {
            #expect(!detail.contains("This scheme does not request"))
        }
        #else
        #expect(!blocked.isAvailable)
        #endif
    }
}
