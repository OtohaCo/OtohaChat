import AgentCatalog
import Foundation

public struct CatalogRefreshResult: Equatable, Sendable {
    public var models: [CatalogModelChoice]
    public var stale: Bool
    public var error: String?

    public init(models: [CatalogModelChoice], stale: Bool, error: String? = nil) {
        self.models = models
        self.stale = stale
        self.error = error
    }
}

public actor CatalogService {
    private let cache = ModelCatalogCache()
    private var lastKnownGood: [UUID: [CatalogModelChoice]] = [:]

    public init() {}

    public func remember(_ models: [CatalogModelChoice], for profileID: UUID) {
        lastKnownGood[profileID] = models
    }

    public func refresh(
        profile: ProviderProfile,
        factory: ProviderFactory,
        apiKey: String?
    ) async -> CatalogRefreshResult {
        let previous = lastKnownGood[profile.id] ?? profile.catalogModels
        do {
            guard let provider = try factory.makeCatalogProvider(profile: profile, apiKey: apiKey) else {
                return CatalogRefreshResult(
                    models: mergeManual(profile, into: previous),
                    stale: false,
                    error: "This provider has no catalog API. Enter a model ID that the Responses endpoint accepts. A /models listing from another product does not imply /responses support."
                )
            }
            let snapshot = try await cache.refresh(using: provider)
            let models = CatalogCapabilityOverlay.merge(
                kind: profile.kind,
                models: snapshot.models.map { CatalogModelChoice(entry: $0) }
            )
            let merged = mergeManual(profile, into: models)
            lastKnownGood[profile.id] = merged
            return CatalogRefreshResult(
                models: merged,
                stale: snapshot.state == .stale,
                error: nil
            )
        } catch {
            let retained = mergeManual(profile, into: previous)
            return CatalogRefreshResult(
                models: retained,
                stale: !retained.isEmpty,
                error: CatalogFailureText.describe(error)
            )
        }
    }

    private func mergeManual(_ profile: ProviderProfile, into models: [CatalogModelChoice]) -> [CatalogModelChoice] {
        switch profile.kind {
        case .applePCC, .appleOnDevice:
            return models
        case .openaiResponses, .anthropic, .deepseekResponses, .localResponses, .compatibleGateway:
            break
        }
        let manual = profile.manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manual.isEmpty else { return models }
        if models.contains(where: { $0.modelName == manual }) { return models }
        return [CatalogModelChoice(modelName: manual, displayName: manual, source: "host_override")] + models
    }
}
