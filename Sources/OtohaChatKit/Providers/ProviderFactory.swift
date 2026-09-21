import AgentAppleProvider
import AgentCatalog
import AgentCore
import AgentModels
import AgentProviders
import Foundation

public enum ProviderFactoryError: Error, Equatable, Sendable, LocalizedError {
    case missingAPIKey
    case missingEndpoint
    case missingModelID
    case appleUnavailable(String)
    case chatCompletionsUnsupported

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add an API key for this model in Settings."
        case .missingEndpoint:
            "Add an endpoint URL in Settings."
        case .missingModelID:
            "Choose or enter a model ID."
        case .appleUnavailable(let reason):
            reason
        case .chatCompletionsUnsupported:
            "This build supports the Responses API only, not Chat Completions."
        }
    }
}

public struct PreparedProvider: Sendable {
    public let profile: ProviderProfile
    public let model: ModelID
    public let provider: any ModelProvider
    public let deployment: AgentModelDeployment
    public let configurationSummary: [String: JSONValue]

    public init(
        profile: ProviderProfile,
        model: ModelID,
        provider: any ModelProvider,
        deployment: AgentModelDeployment,
        configurationSummary: [String: JSONValue]
    ) {
        self.profile = profile
        self.model = model
        self.provider = provider
        self.deployment = deployment
        self.configurationSummary = configurationSummary
    }

    public func makeBinding(
        projector: any AgentContextProjector = AgentIdentityContextProjector()
    ) throws -> AgentModelBinding {
        let resolved: any AgentContextProjector
        if model.provider == "apple-foundation" {
            resolved = AppleTranscriptProjector(base: projector)
        } else {
            resolved = projector
        }
        return try AgentModelBinding(
            profileID: profile.id.uuidString,
            profileRevision: "1",
            model: model,
            provider: provider,
            deployment: deployment,
            configurationSummary: configurationSummary,
            projector: resolved
        )
    }
}

public struct ProviderFactory: Sendable {
    public var transport: any ProviderHTTPTransport
    public var onDeviceStatus: @Sendable () -> AppleRuntimeStatus
    public var pccStatus: @Sendable () -> AppleRuntimeStatus

    public init(
        transport: any ProviderHTTPTransport = URLSessionProviderHTTPTransport(),
        onDeviceStatus: @escaping @Sendable () -> AppleRuntimeStatus = { AppleRuntimeProbe.onDeviceStatus() },
        pccStatus: @escaping @Sendable () -> AppleRuntimeStatus = { AppleRuntimeProbe.pccStatus() }
    ) {
        self.transport = transport
        self.onDeviceStatus = onDeviceStatus
        self.pccStatus = pccStatus
    }

    private var executionTransport: any ProviderHTTPTransport {
        ProviderHTTPErrorTransport(wrapping: transport)
    }

    public func prepare(
        profile: ProviderProfile,
        apiKey: String?,
        modelOverride: String? = nil
    ) throws -> PreparedProvider {
        let modelName = (modelOverride ?? profile.effectiveModelID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch profile.kind {
        case .applePCC:
            return try prepareApplePCC(profile: profile)
        case .appleOnDevice:
            return try prepareAppleOnDevice(profile: profile)
        case .openaiResponses, .compatibleGateway:
            return try prepareOpenAI(profile: profile, apiKey: apiKey, modelName: modelName)
        case .anthropic:
            return try prepareAnthropic(profile: profile, apiKey: apiKey, modelName: modelName)
        case .deepseekResponses:
            return try prepareDeepSeek(profile: profile, apiKey: apiKey, modelName: modelName)
        case .localResponses:
            return try prepareLocal(profile: profile, apiKey: apiKey, modelName: modelName)
        }
    }

    public func makeCatalogProvider(
        profile: ProviderProfile,
        apiKey: String?
    ) throws -> (any ModelCatalogProvider)? {
        switch profile.kind {
        case .applePCC, .appleOnDevice:
            return try StaticModelCatalogProvider(
                scope: try catalogScope(for: profile),
                entries: appleCatalogEntries(for: profile)
            )
        case .openaiResponses, .compatibleGateway:
            let key = try requiredKey(apiKey, allowsEmpty: profile.allowsUnauthenticated)
            let endpoint = try catalogURL(for: profile)
            return try OpenAIModelCatalogProvider(
                apiKey: key,
                endpoint: endpoint,
                serviceInstanceID: profile.serviceInstanceID,
                authorizationScopeID: profile.id.uuidString,
                transport: transport
            )
        case .anthropic:
            let key = try requiredKey(apiKey, allowsEmpty: false)
            let endpoint = try catalogURL(for: profile)
            return try AnthropicModelCatalogProvider(
                apiKey: key,
                endpoint: endpoint,
                serviceInstanceID: profile.serviceInstanceID,
                authorizationScopeID: profile.id.uuidString,
                transport: transport
            )
        case .deepseekResponses:
            let key = try requiredKey(apiKey, allowsEmpty: false)
            let endpoint = try catalogURL(for: profile)
            return try DeepSeekModelCatalogProvider(
                apiKey: key,
                endpoint: endpoint,
                serviceInstanceID: profile.serviceInstanceID,
                authorizationScopeID: profile.id.uuidString,
                transport: transport
            )
        case .localResponses:
            return nil
        }
    }

    private func prepareOpenAI(
        profile: ProviderProfile,
        apiKey: String?,
        modelName: String
    ) throws -> PreparedProvider {
        let key = try requiredKey(apiKey, allowsEmpty: profile.allowsUnauthenticated)
        let endpoint = try executionURL(for: profile)
        guard !modelName.isEmpty else { throw ProviderFactoryError.missingModelID }
        let effort = openaiEffort(profile.reasoning.openaiEffort)
        let summary = profile.reasoning.openaiSummary.map(OpenAIReasoningSummary.init(rawValue:))
        let provider = try OpenAIResponsesProvider(
            apiKey: key,
            endpoint: endpoint,
            maximumOutputTokens: profile.reasoning.maximumOutputTokens,
            reasoningEffort: effort,
            reasoningSummary: summary,
            transport: executionTransport
        )
        let model = ModelID(provider: "openai", name: modelName)
        return PreparedProvider(
            profile: profile,
            model: model,
            provider: provider,
            deployment: try deployment(for: profile, endpoint: endpoint),
            configurationSummary: summaryValues(profile, extra: [
                "reasoningEffort": effort.map { .string($0.rawValue) } ?? .string("service-default"),
                "reasoningSummary": summary.map { .string($0.rawValue) } ?? .null,
            ])
        )
    }

    private func prepareAnthropic(
        profile: ProviderProfile,
        apiKey: String?,
        modelName: String
    ) throws -> PreparedProvider {
        let key = try requiredKey(apiKey, allowsEmpty: false)
        let endpoint = try executionURL(for: profile)
        guard !modelName.isEmpty else { throw ProviderFactoryError.missingModelID }
        let run = AnthropicRunParameters.resolve(
            reasoning: profile.reasoning,
            model: profile.catalogModel(named: modelName),
            maximumOutputTokens: profile.reasoning.maximumOutputTokens
        )
        let provider = try AnthropicProvider(
            apiKey: key,
            endpoint: endpoint,
            maximumOutputTokens: profile.reasoning.maximumOutputTokens,
            thinking: run.thinking,
            effort: run.effort,
            transport: executionTransport
        )
        return PreparedProvider(
            profile: profile,
            model: ModelID(provider: "anthropic", name: modelName),
            provider: provider,
            deployment: try deployment(for: profile, endpoint: endpoint),
            configurationSummary: summaryValues(profile, extra: [
                "thinking": .string(thinkingSummary(run.thinking)),
                "effort": run.effort.map { .string($0.rawValue) } ?? .null,
            ])
        )
    }

    private func prepareDeepSeek(
        profile: ProviderProfile,
        apiKey: String?,
        modelName: String
    ) throws -> PreparedProvider {
        let key = try requiredKey(apiKey, allowsEmpty: false)
        let endpoint = try executionURL(for: profile)
        guard !modelName.isEmpty else { throw ProviderFactoryError.missingModelID }
        let effort = deepseekEffort(profile.reasoning.deepseekEffort)
        let provider = try DeepSeekResponsesProvider(
            apiKey: key,
            endpoint: endpoint,
            maximumOutputTokens: profile.reasoning.maximumOutputTokens,
            reasoningEffort: effort,
            transport: executionTransport
        )
        return PreparedProvider(
            profile: profile,
            model: ModelID(provider: "deepseek", name: modelName),
            provider: provider,
            deployment: try deployment(for: profile, endpoint: endpoint),
            configurationSummary: summaryValues(profile, extra: [
                "reasoningEffort": .string(effort.rawValue),
            ])
        )
    }

    private func prepareLocal(
        profile: ProviderProfile,
        apiKey: String?,
        modelName: String
    ) throws -> PreparedProvider {
        let endpoint = try executionURL(for: profile)
        guard !modelName.isEmpty else { throw ProviderFactoryError.missingModelID }
        let authentication: LocalResponsesAuthentication
        if let apiKey, !apiKey.isEmpty {
            authentication = .bearer(apiKey)
        } else {
            authentication = .none
        }
        var capabilities: ModelCapabilities = [.tools]
        if case .effort = profile.reasoning.deepseekEffort {
            capabilities.insert(.reasoning)
        }
        let provider = try LocalResponsesProvider(
            configuration: .init(
                baseURL: endpoint,
                model: modelName,
                authentication: authentication,
                maximumOutputTokens: profile.reasoning.maximumOutputTokens,
                capabilities: capabilities
            ),
            transport: executionTransport
        )
        return PreparedProvider(
            profile: profile,
            model: ModelID(provider: "local-responses", name: modelName),
            provider: provider,
            deployment: try deployment(for: profile, endpoint: endpoint),
            configurationSummary: summaryValues(profile)
        )
    }

    private func prepareAppleOnDevice(profile: ProviderProfile) throws -> PreparedProvider {
        let status = onDeviceStatus()
        guard status.isAvailable else {
            throw ProviderFactoryError.appleUnavailable(status.detail)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            let responseTokens = AppleGenerationLimits.responseTokens(
                requested: profile.reasoning.maximumOutputTokens
            )
            let provider = try AppleFoundationProvider(
                maximumResponseTokens: responseTokens
            )
            return PreparedProvider(
                profile: profile,
                model: AppleFoundationProvider.modelID,
                provider: provider,
                deployment: try AgentModelDeployment(
                    serviceInstanceID: profile.serviceInstanceID,
                    endpointScope: "apple-foundation-on-device",
                    apiDialect: profile.kind.apiDialect
                ),
                configurationSummary: summaryValues(profile, extra: [
                    "maximumResponseTokens": .number(Decimal(responseTokens)),
                ])
            )
        }
        #endif
        throw ProviderFactoryError.appleUnavailable("On-device Apple models require macOS 26 or iOS 26.")
    }

    private func prepareApplePCC(profile: ProviderProfile) throws -> PreparedProvider {
        let status = pccStatus()
        guard status.isAvailable else {
            throw ProviderFactoryError.appleUnavailable(status.detail)
        }
        #if compiler(>=6.4)
        #if canImport(FoundationModels)
        if #available(macOS 27, iOS 27, *) {
            let responseTokens = AppleGenerationLimits.responseTokens(
                requested: profile.reasoning.maximumOutputTokens
            )
            let provider = try AppleFoundationProvider.privateCloudCompute(
                maximumResponseTokens: responseTokens
            )
            return PreparedProvider(
                profile: profile,
                model: AppleFoundationProvider.privateCloudComputeModelID,
                provider: provider,
                deployment: try AgentModelDeployment(
                    serviceInstanceID: profile.serviceInstanceID,
                    endpointScope: "apple-foundation-pcc",
                    apiDialect: profile.kind.apiDialect
                ),
                configurationSummary: summaryValues(profile, extra: [
                    "qualification": .string("experimental-rc2"),
                    "maximumResponseTokens": .number(Decimal(responseTokens)),
                ])
            )
        }
        #endif
        #endif
        throw ProviderFactoryError.appleUnavailable("Apple Private Cloud Compute requires macOS 27 or iOS 27.")
    }

    private func executionURL(for profile: ProviderProfile) throws -> URL {
        guard let raw = profile.executionURL else { throw ProviderFactoryError.missingEndpoint }
        return try EndpointPolicy.parse(
            raw,
            allowsInsecurePrivateNetworkHTTP: profile.allowsInsecurePrivateNetworkHTTP
        )
    }

    private func catalogURL(for profile: ProviderProfile) throws -> URL {
        let raw = profile.catalogURL ?? profile.executionURL
        guard let raw else { throw ProviderFactoryError.missingEndpoint }
        return try EndpointPolicy.parse(
            raw,
            allowsInsecurePrivateNetworkHTTP: profile.allowsInsecurePrivateNetworkHTTP
        )
    }

    private func deployment(for profile: ProviderProfile, endpoint: URL) throws -> AgentModelDeployment {
        try AgentModelDeployment(
            serviceInstanceID: profile.serviceInstanceID,
            endpointScope: EndpointPolicy.identityScope(for: endpoint),
            apiDialect: profile.kind.apiDialect
        )
    }

    private func catalogScope(for profile: ProviderProfile) throws -> ModelServiceScope {
        try ModelServiceScope(
            provider: profile.kind.sdkProviderID,
            serviceInstanceID: profile.serviceInstanceID,
            endpointScope: profile.kind.apiDialect,
            apiDialect: profile.kind.catalogDialect,
            authorizationScopeID: profile.id.uuidString
        )
    }

    private func appleCatalogEntries(for profile: ProviderProfile) throws -> [ModelCatalogEntry] {
        let scope = try catalogScope(for: profile)
        let model: ModelID
        switch profile.kind {
        case .applePCC: model = AppleFoundationProvider.privateCloudComputeModelID
        default: model = AppleFoundationProvider.modelID
        }
        return [
            ModelCatalogEntry(
                model: model,
                deploymentID: model.name,
                serviceScope: scope,
                displayName: profile.displayName,
                capabilities: .init(
                    multiTurn: .supported,
                    tools: .supported,
                    structuredOutput: .unsupported,
                    reasoning: .unknown,
                    configurableReasoning: .unsupported
                ),
                metadataComplete: false,
                sources: [.init(kind: .documentedContract, reference: "SwiftAgent 1.0.0-rc.3")]
            ),
        ]
    }

    private func requiredKey(_ apiKey: String?, allowsEmpty: Bool) throws -> String {
        if let apiKey, !apiKey.isEmpty { return apiKey }
        if allowsEmpty { return "unauthenticated" }
        throw ProviderFactoryError.missingAPIKey
    }

    private func openaiEffort(_ choice: ReasoningChoice) -> OpenAIReasoningEffort? {
        switch choice {
        case .serviceDefault: nil
        case .disabled, .thinkingDisabled: OpenAIReasoningEffort.disabled
        case .effort(let value): OpenAIReasoningEffort(rawValue: value)
        case .thinkingAdaptive, .thinkingBudgetTokens: nil
        }
    }

    private func thinkingSummary(_ thinking: AnthropicThinking) -> String {
        switch thinking {
        case .disabled: "disabled"
        case .adaptive: "adaptive"
        case .enabled(let tokens): "enabled:\(tokens)"
        }
    }

    private func deepseekEffort(_ choice: ReasoningChoice) -> DeepSeekReasoningEffort {
        switch choice {
        case .serviceDefault: .high
        case .disabled, .thinkingDisabled: .none
        case .effort(let value): DeepSeekReasoningEffort(rawValue: value)
        case .thinkingAdaptive, .thinkingBudgetTokens: .high
        }
    }

    private func summaryValues(
        _ profile: ProviderProfile,
        extra: [String: JSONValue] = [:]
    ) -> [String: JSONValue] {
        var values: [String: JSONValue] = [
            "kind": .string(profile.kind.rawValue),
            "serviceInstanceID": .string(profile.serviceInstanceID),
            "maximumOutputTokens": .number(Decimal(profile.reasoning.maximumOutputTokens)),
        ]
        for (key, value) in extra { values[key] = value }
        return values
    }
}
