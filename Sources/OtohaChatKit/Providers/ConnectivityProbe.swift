import Foundation

public enum ConnectivityCheckKind: String, Sendable {
    case configuration
    case catalog
    case generation
}

public struct ConnectivityProbe: Sendable {
    public var factory: ProviderFactory
    public var catalog: CatalogService

    public init(factory: ProviderFactory, catalog: CatalogService) {
        self.factory = factory
        self.catalog = catalog
    }

    public func validateConfiguration(profile: ProviderProfile, apiKey: String?) -> ConnectivityRecord {
        do {
            if profile.kind.usesHTTP {
                _ = try factory.prepare(profile: profile, apiKey: apiKey)
            } else {
                _ = try factory.prepare(profile: profile, apiKey: nil)
            }
            return ConnectivityRecord(
                configurationSaved: true,
                message: "Configuration is structurally valid. Catalog and generation were not probed."
            )
        } catch {
            return ConnectivityRecord(
                configurationSaved: false,
                message: SecretRedactor.redact(String(describing: error))
            )
        }
    }

    public func checkCatalog(profile: ProviderProfile, apiKey: String?) async -> (ProviderProfile, ConnectivityRecord) {
        var updated = profile
        let result = await catalog.refresh(profile: profile, factory: factory, apiKey: apiKey)
        updated.catalogModels = result.models
        updated.catalogStale = result.stale
        updated.lastCatalogError = result.error
        updated.lastCatalogRefresh = Date()
        let record = ConnectivityRecord(
            configurationSaved: true,
            catalogReachable: result.error == nil,
            message: result.error ?? "Catalog reachable. \(result.models.count) model(s). Generation was not requested."
        )
        updated.lastConnectivity = record
        return (updated, record)
    }
}
