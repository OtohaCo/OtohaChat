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

    @Test func anthropicMediumEffortSendsAdaptiveThinking() async throws {
        let captured = CapturingTransport()
        var profile = ProviderProfile(kind: .anthropic, manualModelID: "claude-opus-4-6")
        profile.reasoning.anthropicThinking = .thinkingDisabled
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
}

private func consume(_ prepared: PreparedProvider, model: String) async {
    let request = ModelRequest(
        model: ModelID(provider: "openai", name: model),
        messages: [.user([.text("hello")])]
    )
    var iterator = prepared.provider.stream(request: request).makeAsyncIterator()
    _ = try? await iterator.next()
}

private func consumeAnthropic(_ prepared: PreparedProvider) async {
    let request = ModelRequest(
        model: ModelID(provider: "anthropic", name: "claude-opus-4-6"),
        messages: [.user([.text("hello")])]
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
