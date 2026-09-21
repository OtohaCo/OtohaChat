import Foundation

/// Whether a configured provider should appear in the model switcher.
public struct ProviderSelection: Equatable, Sendable {
    public var hasAPIKey: Bool
    public var pccAvailable: Bool
    public var onDeviceAvailable: Bool

    public init(hasAPIKey: Bool, pccAvailable: Bool, onDeviceAvailable: Bool) {
        self.hasAPIKey = hasAPIKey
        self.pccAvailable = pccAvailable
        self.onDeviceAvailable = onDeviceAvailable
    }
}

public extension ProviderProfile {
    func isReady(for selection: ProviderSelection) -> Bool {
        guard isEnabled else { return false }
        switch kind {
        case .applePCC:
            return selection.pccAvailable
        case .appleOnDevice:
            return selection.onDeviceAvailable
        case .localResponses:
            return endpointIsConfigured
        case .openaiResponses, .anthropic, .deepseekResponses, .compatibleGateway:
            return selection.hasAPIKey && endpointIsConfigured
        }
    }

    var endpointIsConfigured: Bool {
        switch kind {
        case .applePCC, .appleOnDevice:
            return true
        case .localResponses, .compatibleGateway:
            return !(executionURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openaiResponses, .anthropic, .deepseekResponses:
            return true
        }
    }

    func catalogModel(named name: String) -> CatalogModelChoice? {
        catalogModels.first { $0.modelName == name }
    }

    var pickerModels: [CatalogModelChoice] {
        catalogModels.filter { CatalogDisplayPolicy.isOfferedInChatPicker(kind: kind, modelName: $0.modelName) }
    }
}

/// Host display policy for noisy upstream lists. This does not claim capabilities.
public enum CatalogDisplayPolicy {
    public static func isOfferedInChatPicker(kind: ProviderKind, modelName: String) -> Bool {
        switch kind {
        case .openaiResponses, .compatibleGateway:
            return !excludedOpenAIFragments.contains { modelName.localizedCaseInsensitiveContains($0) }
        case .anthropic, .deepseekResponses, .localResponses, .applePCC, .appleOnDevice:
            return true
        }
    }

    private static let excludedOpenAIFragments = [
        "whisper",
        "tts",
        "dall-e",
        "embedding",
        "moderation",
        "transcribe",
        "realtime",
        "gpt-image",
        "sora-",
        "computer-use",
    ]
}
