import Foundation

public struct ProviderProfile: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var kind: ProviderKind
    public var displayName: String
    public var serviceInstanceID: String
    public var executionURL: String?
    public var catalogURL: String?
    public var allowsUnauthenticated: Bool
    public var allowsInsecurePrivateNetworkHTTP: Bool
    public var manualModelID: String
    public var selectedModelID: String?
    public var catalogModels: [CatalogModelChoice]
    public var catalogStale: Bool
    public var lastCatalogError: String?
    public var lastCatalogRefresh: Date?
    public var lastConnectivity: ConnectivityRecord?
    public var reasoning: ReasoningConfiguration
    public var notes: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        kind: ProviderKind,
        displayName: String? = nil,
        serviceInstanceID: String? = nil,
        executionURL: String? = nil,
        catalogURL: String? = nil,
        allowsUnauthenticated: Bool = false,
        allowsInsecurePrivateNetworkHTTP: Bool = false,
        manualModelID: String = "",
        selectedModelID: String? = nil,
        catalogModels: [CatalogModelChoice] = [],
        catalogStale: Bool = false,
        lastCatalogError: String? = nil,
        lastCatalogRefresh: Date? = nil,
        lastConnectivity: ConnectivityRecord? = nil,
        reasoning: ReasoningConfiguration = .init(),
        notes: String = "",
        isEnabled: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName ?? kind.displayName
        self.serviceInstanceID = serviceInstanceID ?? "\(kind.rawValue)-\(id.uuidString.prefix(8))"
        self.executionURL = executionURL ?? kind.defaultExecutionURL
        self.catalogURL = catalogURL ?? kind.defaultCatalogURL
        self.allowsUnauthenticated = allowsUnauthenticated
        self.allowsInsecurePrivateNetworkHTTP = allowsInsecurePrivateNetworkHTTP
        self.manualModelID = manualModelID
        self.selectedModelID = selectedModelID
        self.catalogModels = catalogModels
        self.catalogStale = catalogStale
        self.lastCatalogError = lastCatalogError
        self.lastCatalogRefresh = lastCatalogRefresh
        self.lastConnectivity = lastConnectivity
        self.reasoning = reasoning
        self.notes = notes
        self.isEnabled = isEnabled
    }

    public var effectiveModelID: String? {
        if let selectedModelID, !selectedModelID.isEmpty { return selectedModelID }
        let manual = manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return manual.isEmpty ? nil : manual
    }

    public var credentialAccount: String {
        CredentialAccount.apiKey(profileID: id)
    }
}

public struct ConnectivityRecord: Equatable, Sendable, Codable {
    public var checkedAt: Date
    public var configurationSaved: Bool
    public var catalogReachable: Bool?
    public var generationSucceeded: Bool?
    public var toolLoopSucceeded: Bool?
    public var message: String

    public init(
        checkedAt: Date = Date(),
        configurationSaved: Bool,
        catalogReachable: Bool? = nil,
        generationSucceeded: Bool? = nil,
        toolLoopSucceeded: Bool? = nil,
        message: String
    ) {
        self.checkedAt = checkedAt
        self.configurationSaved = configurationSaved
        self.catalogReachable = catalogReachable
        self.generationSucceeded = generationSucceeded
        self.toolLoopSucceeded = toolLoopSucceeded
        self.message = message
    }
}

public struct ProviderSettingsDocument: Equatable, Sendable, Codable {
    public var profiles: [ProviderProfile]
    public var defaultProfileID: UUID?
    public var autoSuggestSkills: Bool
    public var workspaceBookmark: Data?
    public var globalSkillsBookmark: Data?

    public init(
        profiles: [ProviderProfile] = ProviderSettingsDocument.builtInProfiles(),
        defaultProfileID: UUID? = nil,
        autoSuggestSkills: Bool = false,
        workspaceBookmark: Data? = nil,
        globalSkillsBookmark: Data? = nil
    ) {
        self.profiles = profiles
        self.defaultProfileID = defaultProfileID ?? profiles.first(where: { $0.kind == .applePCC })?.id
        self.autoSuggestSkills = autoSuggestSkills
        self.workspaceBookmark = workspaceBookmark
        self.globalSkillsBookmark = globalSkillsBookmark
    }

    public static func builtInProfiles() -> [ProviderProfile] {
        [
            ProviderProfile(
                kind: .applePCC,
                displayName: "Apple PCC",
                serviceInstanceID: "apple-pcc-default",
                selectedModelID: "private-cloud-compute",
                notes: "Experimental in SwiftAgent 1.0.0-rc.3. No API key. Availability depends on Apple account, device, region, and a granted entitlement.",
                isEnabled: true
            ),
            ProviderProfile(
                kind: .appleOnDevice,
                displayName: "Apple on-device",
                serviceInstanceID: "apple-on-device-default",
                selectedModelID: "on-device",
                isEnabled: true
            ),
            ProviderProfile(
                kind: .openaiResponses,
                displayName: "OpenAI"
            ),
            ProviderProfile(
                kind: .anthropic,
                displayName: "Anthropic"
            ),
            ProviderProfile(
                kind: .deepseekResponses,
                displayName: "DeepSeek"
            ),
            ProviderProfile(
                kind: .localResponses,
                displayName: "Local Responses",
                allowsUnauthenticated: true,
                notes: "RC3 speaks the Responses API only. A /models listing does not mean /responses is implemented."
            ),
            ProviderProfile(
                kind: .compatibleGateway,
                displayName: "Compatible gateway",
                notes: "OpenAI Responses-compatible gateways, including SUB2API-style /responses proxies. Chat Completions is not supported."
            ),
        ]
    }
}
