import AgentCatalog
import AgentModels
import AgentProviders
import OtohaChatKit
import Foundation
import Testing

struct AnthropicCatalogTests {
    @Test func swiftAgentRC3ReadsLiveAnthropicCapabilityObjects() async throws {
        let transport = SequentialHTTPTransport(bodies: [Data(Self.liveObjectJSON.utf8)])
        let provider = try AnthropicModelCatalogProvider(
            apiKey: "fixture-secret",
            endpoint: URL(string: "https://api.anthropic.com/v1/models")!,
            serviceInstanceID: "anthropic-workspace",
            transport: transport
        )
        let page = try await provider.listModels(.init())
        let model = try #require(page.models.first)
        #expect(model.model.name == "claude-opus-4-6")
        #expect(model.displayName == "Claude Opus 4.6")
        #expect(model.capabilities.configurableReasoning == .supported)
        #expect(model.reasoningControls.contains { $0.kind == .effort && $0.allowedValues?.contains("high") == true })
        #expect(model.reasoningControls.contains { $0.kind == .thinkingMode && $0.allowedValues?.contains("adaptive") == true })
        #expect(page.nextCursor == nil)
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test func swiftAgentRC3StillReadsLegacyArrayCapabilityShape() async throws {
        let transport = SequentialHTTPTransport(bodies: [Data(Self.legacyArrayJSON.utf8)])
        let provider = try AnthropicModelCatalogProvider(
            apiKey: "fixture-secret",
            endpoint: URL(string: "https://api.anthropic.com/v1/models")!,
            serviceInstanceID: "anthropic-workspace",
            transport: transport
        )
        let model = try #require(try await provider.listModels(.init()).models.first)
        #expect(model.model.name == "claude-future")
        #expect(model.reasoningControls.first { $0.kind == .effort }?.allowedValues == ["low", "high", "future"])
        #expect(model.reasoningControls.first { $0.kind == .thinkingMode }?.allowedValues == ["adaptive", "enabled"])
    }

    @Test func extraCatalogKeysDoNotInvalidateThePage() async throws {
        let transport = SequentialHTTPTransport(bodies: [Data(Self.liveObjectJSON.utf8)])
        let provider = try AnthropicModelCatalogProvider(
            apiKey: "fixture-secret",
            endpoint: URL(string: "https://api.anthropic.com/v1/models")!,
            serviceInstanceID: "anthropic-workspace",
            transport: transport
        )
        let page = try await provider.listModels(.init())
        #expect(page.models.count == 1)
    }

    @Test func nestedCapabilityObjectsStayFailClosedWithoutExplicitSupport() async throws {
        let transport = SequentialHTTPTransport(bodies: [Data(Self.unsupportedObjectJSON.utf8)])
        let provider = try AnthropicModelCatalogProvider(
            apiKey: "fixture-secret",
            endpoint: URL(string: "https://api.anthropic.com/v1/models")!,
            serviceInstanceID: "anthropic-workspace",
            transport: transport
        )
        let model = try #require(try await provider.listModels(.init()).models.first)
        let effort = try #require(model.reasoningControls.first { $0.kind == .effort })
        #expect(effort.allowedValues == nil)
        #expect(model.capabilities.configurableReasoning == .unsupported)
    }

    @Test func catalogRefreshSurfacesLiveAnthropicModelsInsteadOfInvalidResponse() async {
        let catalog = CatalogService()
        var profile = ProviderProfile(kind: .anthropic, isEnabled: true)
        profile.manualModelID = "claude-sonnet-4-6"
        let factory = ProviderFactory(
            transport: SequentialHTTPTransport(bodies: [Data(Self.liveObjectJSON.utf8)]),
            onDeviceStatus: { .unsupportedSystem("unused") },
            pccStatus: { .unsupportedSystem("unused") }
        )
        let result = await catalog.refresh(profile: profile, factory: factory, apiKey: "sk-ant-test")
        #expect(result.error == nil)
        #expect(result.models.contains(where: { $0.modelName == "claude-opus-4-6" }))
        #expect(result.models.contains(where: { $0.modelName == "claude-sonnet-4-6" }))
    }

    @Test func catalogFailureTextDoesNotDumpSDKError() {
        let text = CatalogFailureText.describe(ModelCatalogError(kind: .invalidResponse))
        #expect(!text.contains("invalid_response"))
        #expect(text.contains("could not read"))
    }

    private static let liveObjectJSON = """
    {"data":[{"id":"claude-opus-4-6","display_name":"Claude Opus 4.6","created_at":"2026-02-04T00:00:00Z","type":"model","capabilities":{"batch":{"supported":true},"effort":{"supported":true,"low":{"supported":true},"medium":{"supported":true},"high":{"supported":true},"max":{"supported":true},"xhigh":{"supported":true}},"structured_outputs":{"supported":true},"thinking":{"supported":true,"types":{"adaptive":{"supported":true},"enabled":{"supported":true}}}},"max_input_tokens":200000,"max_tokens":64000}],"has_more":false,"first_id":"claude-opus-4-6","last_id":"claude-opus-4-6"}
    """

    private static let legacyArrayJSON = """
    {"data":[{"id":"claude-future","display_name":"Claude Future","capabilities":{"effort":{"supported":true,"values":["low","high","future"]},"thinking":{"supported":true,"types":["adaptive","enabled"]}},"max_input_tokens":200000,"max_tokens":64000}],"has_more":false,"last_id":"claude-future"}
    """

    private static let unsupportedObjectJSON = """
    {"data":[{"id":"claude-unsupported","capabilities":{"effort":{"supported":false,"experimental":{"supported":true}},"thinking":{"supported":false,"types":{"enabled":{"supported":true}}}}}],"has_more":false,"last_id":"claude-unsupported"}
    """
}

final class SequentialHTTPTransport: ProviderHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Data]
    private let status: Int
    private(set) var requests: [URLRequest] = []

    init(bodies: [Data], status: Int = 200) {
        self.bodies = bodies
        self.status = status
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<ProviderHTTPEvent, Error> {
        lock.lock()
        requests.append(request)
        let body = bodies.isEmpty ? nil : bodies.removeFirst()
        let status = self.status
        lock.unlock()
        return AsyncThrowingStream { continuation in
            guard let body else {
                continuation.finish(throwing: ModelProviderError(kind: .transport, message: "Fixture responses exhausted."))
                return
            }
            continuation.yield(.response(status: status, headers: ["Content-Type": "application/json"]))
            continuation.yield(.data(body))
            continuation.finish()
        }
    }
}
