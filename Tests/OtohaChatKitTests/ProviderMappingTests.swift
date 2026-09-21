import AgentCatalog
import AgentModels
import AgentProviders
import OtohaChatKit
import Foundation
import Testing

struct ProviderMappingTests {
    @Test func openaiServiceDefaultOmitsEffortAndExplicitValueIsSent() async throws {
        let omitted = CapturingTransport()
        var profile = ProviderProfile(kind: .openaiResponses, manualModelID: "gpt-test")
        profile.reasoning.openaiEffort = .serviceDefault
        let factory = ProviderFactory(
            transport: omitted,
            onDeviceStatus: { .unsupportedSystem("unused") },
            pccStatus: { .unsupportedSystem("unused") }
        )
        let prepared = try factory.prepare(profile: profile, apiKey: "test-key-not-real")
        await consume(prepared, model: "gpt-test")
        let body = try omitted.firstJSON()
        #expect(body["reasoning"] == nil)

        let captured = CapturingTransport()
        profile.reasoning.openaiEffort = .effort("xhigh")
        let factory2 = ProviderFactory(
            transport: captured,
            onDeviceStatus: { .unsupportedSystem("unused") },
            pccStatus: { .unsupportedSystem("unused") }
        )
        let prepared2 = try factory2.prepare(profile: profile, apiKey: "test-key-not-real")
        await consume(prepared2, model: "gpt-test")
        let body2 = try captured.firstJSON()
        let reasoning = body2["reasoning"] as? [String: Any]
        #expect(reasoning?["effort"] as? String == "xhigh")
        #expect(prepared2.configurationSummary["reasoningEffort"] == .string("xhigh"))
    }

    @Test func disabledIsDistinctFromServiceDefault() async throws {
        let captured = CapturingTransport()
        var profile = ProviderProfile(kind: .openaiResponses, manualModelID: "gpt-test")
        profile.reasoning.openaiEffort = .disabled
        let factory = ProviderFactory(transport: captured)
        let prepared = try factory.prepare(profile: profile, apiKey: "test-key-not-real")
        await consume(prepared, model: "gpt-test")
        let reasoning = try captured.firstJSON()["reasoning"] as? [String: Any]
        #expect(reasoning?["effort"] as? String == "none")
    }

    @Test func unknownCapabilityIsNotTreatedAsSupported() {
        let presentation = ReasoningCapabilityMapper.presentation(
            kind: .openaiResponses,
            reasoning: .unknown,
            configurable: .unknown,
            controls: []
        )
        #expect(presentation == .unknown)
        let none = ReasoningCapabilityMapper.presentation(
            kind: .openaiResponses,
            reasoning: .unsupported,
            configurable: .unknown,
            controls: []
        )
        #expect(none == .none)
    }

    @Test func catalogsAreScopedByServiceInstance() throws {
        let first = ProviderProfile(kind: .openaiResponses, serviceInstanceID: "a")
        let second = ProviderProfile(kind: .openaiResponses, serviceInstanceID: "b")
        #expect(first.serviceInstanceID != second.serviceInstanceID)
        #expect(first.credentialAccount != second.credentialAccount)
    }

    @Test func reasoningSliderMapsOpenAIEffort() {
        var reasoning = ReasoningConfiguration()
        reasoning.setIntensity(.off, for: .openaiResponses)
        #expect(reasoning.openaiEffort == .disabled)
        reasoning.setIntensity(.max, for: .openaiResponses)
        #expect(reasoning.openaiEffort == .effort("xhigh"))
        #expect(reasoning.intensity(for: .openaiResponses) == .max)
        #expect(ReasoningIntensity.max.label == "Max")
    }

    @Test func leftoverAnthropicEffortDoesNotForceAdaptiveOnANewChat() async throws {
        let captured = CapturingTransport()
        var profile = ProviderProfile(kind: .anthropic, manualModelID: "claude-sonnet-4-5")
        profile.catalogModels = [Self.sonnet45]
        profile.reasoning.anthropicThinking = .thinkingDisabled
        profile.reasoning.anthropicEffort = "medium"
        let factory = ProviderFactory(transport: captured)
        let prepared = try factory.prepare(profile: profile, apiKey: "test-key-not-real")
        await consumeAnthropic(prepared)
        let body = try captured.firstJSON()
        let thinking = body["thinking"] as? [String: Any]
        #expect(thinking?["type"] as? String == "disabled")
        #expect(body["output_config"] == nil)
    }

    @Test func sonnet45TurnsAdaptiveIntoEnabledThinkingWithoutEffort() async throws {
        let captured = CapturingTransport()
        var profile = ProviderProfile(kind: .anthropic, manualModelID: "claude-sonnet-4-5")
        profile.catalogModels = [Self.sonnet45]
        profile.reasoning.anthropicThinking = .thinkingAdaptive
        profile.reasoning.anthropicEffort = "medium"
        let factory = ProviderFactory(transport: captured)
        let prepared = try factory.prepare(profile: profile, apiKey: "test-key-not-real")
        await consumeAnthropic(prepared)
        let body = try captured.firstJSON()
        let thinking = body["thinking"] as? [String: Any]
        #expect(thinking?["type"] as? String == "enabled")
        #expect((thinking?["budget_tokens"] as? NSNumber)?.intValue == 1_024)
        #expect(body["output_config"] == nil)
    }

    @Test func opusKeepsAdaptiveThinkingAndEffort() async throws {
        let captured = CapturingTransport()
        var profile = ProviderProfile(kind: .anthropic, manualModelID: "claude-opus-4-6")
        profile.catalogModels = [Self.opus46]
        profile.reasoning.anthropicThinking = .thinkingAdaptive
        profile.reasoning.anthropicEffort = "medium"
        let factory = ProviderFactory(transport: captured)
        let prepared = try factory.prepare(profile: profile, apiKey: "test-key-not-real")
        await consumeAnthropic(prepared)
        let body = try captured.firstJSON()
        let thinking = body["thinking"] as? [String: Any]
        #expect(thinking?["type"] as? String == "adaptive")
        let output = body["output_config"] as? [String: Any]
        #expect(output?["effort"] as? String == "medium")
    }

    @Test func sonnet5TurnsEnabledBudgetIntoAdaptive() async throws {
        let captured = CapturingTransport()
        var profile = ProviderProfile(kind: .anthropic, manualModelID: "claude-sonnet-5")
        profile.catalogModels = [Self.sonnet5]
        profile.reasoning.anthropicThinking = .thinkingBudgetTokens(4_096)
        let factory = ProviderFactory(transport: captured)
        let prepared = try factory.prepare(profile: profile, apiKey: "test-key-not-real")
        await consumeAnthropic(prepared)
        let thinking = try captured.firstJSON()["thinking"] as? [String: Any]
        #expect(thinking?["type"] as? String == "adaptive")
    }

    @Test func anthropicChatRequestMatchesHostToolLoop() async throws {
        let captured = CapturingTransport()
        var profile = ProviderProfile(kind: .anthropic, manualModelID: "claude-sonnet-4-5")
        profile.catalogModels = [Self.sonnet45]
        let factory = ProviderFactory(transport: captured)
        let prepared = try factory.prepare(profile: profile, apiKey: "test-key-not-real")
        await consumeAnthropic(prepared, tools: [
            .init(name: CalculatorTool.name, description: CalculatorTool.description, inputSchema: CalculatorTool.inputSchema.json),
            .init(name: DateTimeTool.name, description: DateTimeTool.description, inputSchema: DateTimeTool.inputSchema.json),
            .init(name: WorkspaceReadTool.name, description: WorkspaceReadTool.description, inputSchema: WorkspaceReadTool.inputSchema.json),
            .init(name: AppNotesReadTool.name, description: AppNotesReadTool.description, inputSchema: AppNotesReadTool.inputSchema.json),
            .init(name: AppNotesTool.name, description: AppNotesTool.description, inputSchema: AppNotesTool.inputSchema.json),
        ])
        let body = captured.firstRawUTF8()
        #expect(body.contains(#""thinking":{"type":"disabled"}"#) || body.contains(#""type":"disabled"#))
        #expect(body.contains("calculator"))
        #expect(!body.contains("additionalProperties"))
        #expect(!body.contains(#""required":[]"#))
    }

    @Test func anthropicHTTP400SurfacesVendorMessage() async throws {
        let payload = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"adaptive thinking is not supported on this model"}}"#.utf8)
        let factory = ProviderFactory(
            transport: SequentialHTTPTransport(bodies: [payload], status: 400)
        )
        var profile = ProviderProfile(kind: .anthropic, manualModelID: "claude-sonnet-4-5")
        profile.catalogModels = [Self.sonnet45]
        let prepared = try factory.prepare(profile: profile, apiKey: "test-key-not-real")
        let request = ModelRequest(
            model: prepared.model,
            messages: [.user([.text("hello")])]
        )
        var iterator = prepared.provider.stream(request: request).makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("expected the provider to throw")
        } catch let error as ModelProviderError {
            #expect(error.message.contains("adaptive thinking is not supported"))
            #expect(!error.message.hasPrefix("Provider HTTP request failed"))
        }
    }

    private static let sonnet45 = CatalogModelChoice(
        modelName: "claude-sonnet-4-5",
        source: "upstream_api",
        reasoning: ModelCatalogSupport.supported.rawValue,
        configurableReasoning: ModelCatalogSupport.supported.rawValue,
        thinkingValues: ["enabled"],
        tokenBudgetMinimum: 1_024,
        tokenBudgetMaximum: 4_095
    )

    private static let opus46 = CatalogModelChoice(
        modelName: "claude-opus-4-6",
        source: "upstream_api",
        reasoning: ModelCatalogSupport.supported.rawValue,
        configurableReasoning: ModelCatalogSupport.supported.rawValue,
        effortValues: ["low", "medium", "high"],
        thinkingValues: ["adaptive", "enabled"]
    )

    private static let sonnet5 = CatalogModelChoice(
        modelName: "claude-sonnet-5",
        source: "upstream_api",
        reasoning: ModelCatalogSupport.supported.rawValue,
        configurableReasoning: ModelCatalogSupport.supported.rawValue,
        effortValues: ["low", "medium", "high", "max"],
        thinkingValues: ["adaptive"]
    )
}

private func consume(_ prepared: PreparedProvider, model: String) async {
    let request = ModelRequest(
        model: ModelID(provider: "openai", name: model),
        messages: [.user([.text("hello")])]
    )
    var iterator = prepared.provider.stream(request: request).makeAsyncIterator()
    _ = try? await iterator.next()
}

private func consumeAnthropic(_ prepared: PreparedProvider, tools: [ModelToolDefinition] = []) async {
    let request = ModelRequest(
        model: prepared.model,
        messages: [
            .system(AppInstructions.base),
            .user([.text("hello")]),
        ],
        tools: tools
    )
    var iterator = prepared.provider.stream(request: request).makeAsyncIterator()
    _ = try? await iterator.next()
}

final class CapturingTransport: ProviderHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func stream(_ request: URLRequest) -> AsyncThrowingStream<ProviderHTTPEvent, Error> {
        lock.lock()
        requests.append(request)
        lock.unlock()
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: CancellationError())
        }
    }

    func firstRawUTF8() -> String {
        lock.lock()
        let request = requests.first
        lock.unlock()
        guard let body = request?.httpBody, let text = String(data: body, encoding: .utf8) else { return "" }
        return text
    }

    func firstJSON() throws -> [String: Any] {
        lock.lock()
        let request = requests.first
        lock.unlock()
        guard let body = request?.httpBody else { throw TestTransportError.missingBody }
        let object = try JSONSerialization.jsonObject(with: body)
        guard let json = object as? [String: Any] else { throw TestTransportError.missingBody }
        return json
    }
}

private enum TestTransportError: Error { case missingBody }
