import Foundation

/// Chat execution backends supported by SwiftAgent 1.0.0-rc.3.
public enum ProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case applePCC
    case appleOnDevice
    case openaiResponses
    case anthropic
    case deepseekResponses
    case localResponses
    case compatibleGateway

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .applePCC: "Apple Private Cloud Compute"
        case .appleOnDevice: "Apple on-device"
        case .openaiResponses: "OpenAI Responses"
        case .anthropic: "Anthropic"
        case .deepseekResponses: "DeepSeek Responses"
        case .localResponses: "Local Responses"
        case .compatibleGateway: "Compatible Responses gateway"
        }
    }

    public var sdkProviderID: String {
        switch self {
        case .applePCC, .appleOnDevice: "apple-foundation"
        case .openaiResponses, .compatibleGateway: "openai"
        case .anthropic: "anthropic"
        case .deepseekResponses: "deepseek"
        case .localResponses: "local-responses"
        }
    }

    public var apiDialect: String {
        switch self {
        case .applePCC: "apple-pcc"
        case .appleOnDevice: "apple-on-device"
        case .openaiResponses, .compatibleGateway: "openai-responses"
        case .anthropic: "anthropic-messages"
        case .deepseekResponses: "deepseek-responses"
        case .localResponses: "local-responses"
        }
    }

    public var catalogDialect: String {
        switch self {
        case .openaiResponses, .compatibleGateway: "openai-models"
        case .anthropic: "anthropic-models"
        case .deepseekResponses: "deepseek-models"
        case .localResponses: "local-responses-models"
        case .applePCC, .appleOnDevice: "apple-foundation"
        }
    }

    public var defaultExecutionURL: String? {
        switch self {
        case .openaiResponses: "https://api.openai.com/v1/responses"
        case .anthropic: "https://api.anthropic.com/v1/messages"
        case .deepseekResponses: "https://api.deepseek.com/responses"
        case .compatibleGateway: nil
        case .localResponses: "http://127.0.0.1:11434/v1"
        case .applePCC, .appleOnDevice: nil
        }
    }

    public var defaultCatalogURL: String? {
        switch self {
        case .openaiResponses: "https://api.openai.com/v1/models"
        case .anthropic: "https://api.anthropic.com/v1/models"
        case .deepseekResponses: "https://api.deepseek.com/models"
        default: nil
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .applePCC, .appleOnDevice: false
        case .localResponses: false
        default: true
        }
    }

    public var usesHTTP: Bool {
        switch self {
        case .applePCC, .appleOnDevice: false
        default: true
        }
    }

    /// Responses-compatible HTTP APIs. Chat Completions is not supported in RC3.
    public var responsesCompatible: Bool {
        switch self {
        case .openaiResponses, .deepseekResponses, .localResponses, .compatibleGateway: true
        case .anthropic, .applePCC, .appleOnDevice: false
        }
    }
}

/// Decision providers are not chat models. Kept out of the ordinary model picker.
public enum DecisionProviderKind: String, Codable, Sendable {
    case jev
    case typesafe
}
