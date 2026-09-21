import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum AppleRuntimeStatus: Equatable, Sendable {
    case available
    case unsupportedSystem(String)
    case entitlementMissing(String)
    case modelUnavailable(String)
    case undetermined(String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var title: String {
        switch self {
        case .available: "Available"
        case .unsupportedSystem: "Not supported on this system"
        case .entitlementMissing: "Signing or entitlement is insufficient"
        case .modelUnavailable: "Model or service is unavailable"
        case .undetermined: "Cannot determine availability"
        }
    }

    public var detail: String {
        switch self {
        case .available:
            return "This Apple model path is ready on the current device."
        case .unsupportedSystem(let reason),
             .entitlementMissing(let reason),
             .modelUnavailable(let reason),
             .undetermined(let reason):
            return reason
        }
    }
}

public enum AppleRuntimeProbe: Sendable {
    public static let pccEntitlement = "com.apple.developer.private-cloud-compute"

    public static func onDeviceStatus() -> AppleRuntimeStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            return inspectOnDeviceModel()
        }
        return .unsupportedSystem("On-device Apple models require macOS 26 or iOS 26.")
        #else
        return .unsupportedSystem("This build does not include FoundationModels.")
        #endif
    }

    public static func pccStatus(pccBuildEnabled: Bool = Self.isPCCBuildEnabled) -> AppleRuntimeStatus {
        #if compiler(>=6.4)
        if #available(macOS 27, iOS 27, *) {
            #if os(macOS)
            switch entitlementState(pccEntitlement) {
            case .present:
                #if canImport(FoundationModels)
                return inspectPCCModel()
                #else
                return .unsupportedSystem("This build does not include FoundationModels.")
                #endif
            case .absent:
                if !pccBuildEnabled {
                    return .entitlementMissing(
                        "This scheme does not request the Private Cloud Compute entitlement. Use a Release or OtohaChat-PCC build with a development team that Apple has granted the entitlement."
                    )
                }
                return .entitlementMissing(
                    "The running binary is not signed with \(pccEntitlement). Adding an entitlements file does not grant Apple authorization."
                )
            case .unknown(let reason):
                return .undetermined(reason)
            }
            #else
            // App-target compilation flags do not reach OtohaChatKit. iOS also
            // cannot inspect SecTask, so availability comes from the system
            // model API, which fails closed without a signed PCC entitlement.
            #if canImport(FoundationModels)
            return inspectPCCModel()
            #else
            return .unsupportedSystem("This build does not include FoundationModels.")
            #endif
            #endif
        }
        return .unsupportedSystem("Apple Private Cloud Compute requires macOS 27 or iOS 27.")
        #else
        return .unsupportedSystem("This compiler cannot build the RC3 PCC adapter (Swift 6.4 or later is required).")
        #endif
    }

    public static var isPCCBuildEnabled: Bool {
        #if OTOHACHAT_PCC
        true
        #else
        false
        #endif
    }

    public enum EntitlementState: Equatable, Sendable {
        case present
        case absent
        case unknown(String)
    }

    public static func entitlementState(_ name: String) -> EntitlementState {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else {
            return .unknown("Could not inspect the current code-signing task.")
        }
        var error: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(task, name as CFString, &error)
        if let error {
            let copy = error.takeRetainedValue()
            return .unknown("Entitlement inspection failed: \(copy.localizedDescription)")
        }
        if value == nil { return .absent }
        if let flag = value as? Bool { return flag ? .present : .absent }
        if let number = value as? NSNumber { return number.boolValue ? .present : .absent }
        return .present
        #else
        return .unknown("iOS does not expose live code-signing task inspection. PCC status comes from the system model API, not from the entitlements file.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26, iOS 26, *)
    private static func inspectOnDeviceModel() -> AppleRuntimeStatus {
        mapAvailability(SystemLanguageModel.default.availability, serviceName: "The on-device Apple model")
    }

    #if compiler(>=6.4)
    @available(macOS 27, iOS 27, *)
    private static func inspectPCCModel() -> AppleRuntimeStatus {
        switch PrivateCloudComputeLanguageModel().availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unsupportedSystem("Apple Private Cloud Compute is not supported on this device.")
            case .systemNotReady:
                return .modelUnavailable("Apple Private Cloud Compute is not ready on this system.")
            @unknown default:
                return .undetermined("Apple Private Cloud Compute is unavailable for a reason this app does not classify.")
            }
        @unknown default:
            return .undetermined("Apple Private Cloud Compute reported an unrecognized availability value.")
        }
    }
    #endif

    @available(macOS 26, iOS 26, *)
    private static func mapAvailability(
        _ availability: SystemLanguageModel.Availability,
        serviceName: String
    ) -> AppleRuntimeStatus {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return mapUnavailable(reason, serviceName: serviceName)
        @unknown default:
            return .undetermined("\(serviceName) reported an unrecognized availability value.")
        }
    }

    @available(macOS 26, iOS 26, *)
    private static func mapUnavailable(
        _ reason: SystemLanguageModel.Availability.UnavailableReason,
        serviceName: String
    ) -> AppleRuntimeStatus {
        switch reason {
        case .deviceNotEligible:
            return .unsupportedSystem("\(serviceName) is not supported on this device.")
        case .appleIntelligenceNotEnabled:
            return .modelUnavailable("Apple Intelligence is turned off for this account or device.")
        case .modelNotReady:
            return .modelUnavailable("\(serviceName) is not ready yet. Wait for the model to finish downloading.")
        @unknown default:
            return .undetermined("\(serviceName) is unavailable for a reason this app does not classify.")
        }
    }
    #endif
}
