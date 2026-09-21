import AgentCatalog
import Foundation

/// Host-facing copy for a failed catalog refresh. Do not dump SDK error dumps.
public enum CatalogFailureText {
    public static func describe(_ error: any Error) -> String {
        SecretRedactor.redact(raw(error))
    }

    private static func raw(_ error: any Error) -> String {
        if let catalog = error as? ModelCatalogError {
            return message(catalog)
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        return "The model list could not be loaded."
    }

    private static func message(_ error: ModelCatalogError) -> String {
        switch error.kind {
        case .authentication:
            "The API key was rejected. Use a provider Console key, then tap Refresh models."
        case .permissionDenied:
            "This key does not have permission to list models."
        case .rateLimited:
            "The provider rate-limited the model list. Wait and tap Refresh models."
        case .unavailable:
            "The model list service is unavailable. Try again later."
        case .transport:
            "Could not reach the model list endpoint."
        case .invalidResponse:
            "The provider returned a model list this app could not read."
        case .invalidConfiguration:
            "The catalog URL or API key is not valid."
        case .responseTooLarge:
            "The model list was larger than this app will load."
        default:
            "The model list could not be loaded."
        }
    }
}
