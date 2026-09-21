import AgentCatalog
import Foundation

/// SwiftAgent catalogs are advisory. When a list endpoint does not report
/// reasoning controls, the host may attach the adapter's documented contract
/// without pretending those values came from `/models`.
public enum CatalogCapabilityOverlay {
    public static func merge(kind: ProviderKind, models: [CatalogModelChoice]) -> [CatalogModelChoice] {
        models.map { merge(kind: kind, model: $0) }
    }

    public static func merge(kind: ProviderKind, model: CatalogModelChoice) -> CatalogModelChoice {
        guard model.reasoningSupport == .unknown,
              model.configurableReasoningSupport == .unknown,
              (model.effortValues ?? []).isEmpty,
              (model.thinkingValues ?? []).isEmpty
        else {
            return model
        }
        guard CatalogDisplayPolicy.isOfferedInChatPicker(kind: kind, modelName: model.modelName) else {
            return model
        }
        var copy = model
        switch kind {
        case .openaiResponses, .compatibleGateway:
            copy.configurableReasoning = ModelCatalogSupport.supported.rawValue
            copy.effortValues = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
            copy.usedHostManifest = true
        case .deepseekResponses:
            copy.configurableReasoning = ModelCatalogSupport.supported.rawValue
            copy.effortValues = ["none", "low", "medium", "high", "max"]
            copy.usedHostManifest = true
        case .anthropic:
            copy.configurableReasoning = ModelCatalogSupport.supported.rawValue
            copy.effortValues = ["low", "medium", "high", "max"]
            copy.thinkingValues = ["adaptive", "enabled"]
            copy.usedHostManifest = true
        case .applePCC, .appleOnDevice, .localResponses:
            break
        }
        return copy
    }
}
