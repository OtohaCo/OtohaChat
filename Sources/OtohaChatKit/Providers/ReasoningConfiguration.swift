import AgentCatalog
import Foundation

/// Per-run native reasoning choice. Omitted parameters use the service default
/// where the RC3 adapter allows omission.
public enum ReasoningChoice: Equatable, Hashable, Sendable, Codable {
    case serviceDefault
    case disabled
    case effort(String)
    case thinkingDisabled
    case thinkingAdaptive
    case thinkingBudgetTokens(Int)

    public var summaryLabel: String {
        switch self {
        case .serviceDefault: "Service default"
        case .disabled: "Reasoning off"
        case .effort(let value): "Effort \(value)"
        case .thinkingDisabled: "Thinking off"
        case .thinkingAdaptive: "Adaptive thinking"
        case .thinkingBudgetTokens(let tokens): "Thinking budget \(tokens)"
        }
    }
}

/// Composer slider steps, from off to maximum effort.
public enum ReasoningIntensity: Int, CaseIterable, Sendable, Codable {
    case off = 0
    case low = 1
    case medium = 2
    case high = 3
    case max = 4

    public var label: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Max"
        }
    }
}

public struct ReasoningConfiguration: Equatable, Sendable, Codable {
    public var openaiEffort: ReasoningChoice
    public var openaiSummary: String?
    public var anthropicThinking: ReasoningChoice
    public var anthropicEffort: String?
    public var deepseekEffort: ReasoningChoice
    public var maximumOutputTokens: Int

    public init(
        openaiEffort: ReasoningChoice = .serviceDefault,
        openaiSummary: String? = nil,
        anthropicThinking: ReasoningChoice = .thinkingDisabled,
        anthropicEffort: String? = nil,
        deepseekEffort: ReasoningChoice = .effort("high"),
        maximumOutputTokens: Int = 4_096
    ) {
        self.openaiEffort = openaiEffort
        self.openaiSummary = openaiSummary
        self.anthropicThinking = anthropicThinking
        self.anthropicEffort = anthropicEffort
        self.deepseekEffort = deepseekEffort
        self.maximumOutputTokens = maximumOutputTokens
    }

    public func configurationSummary(for kind: ProviderKind) -> [String: String] {
        var fields: [String: String] = ["maximumOutputTokens": String(maximumOutputTokens)]
        switch kind {
        case .openaiResponses, .compatibleGateway:
            fields["openaiEffort"] = openaiEffort.summaryLabel
            if let openaiSummary { fields["openaiSummary"] = openaiSummary }
        case .anthropic:
            fields["anthropicThinking"] = anthropicThinking.summaryLabel
            if let anthropicEffort { fields["anthropicEffort"] = anthropicEffort }
        case .deepseekResponses:
            fields["deepseekEffort"] = deepseekEffort.summaryLabel
        case .localResponses, .applePCC, .appleOnDevice:
            break
        }
        return fields
    }

    public func showsIntensitySlider(for kind: ProviderKind) -> Bool {
        showsReasoningControls(for: nil, kind: kind)
    }

    public func showsReasoningControls(for model: CatalogModelChoice?, kind: ProviderKind) -> Bool {
        if let model {
            return model.hasAdjustableReasoning
        }
        switch kind {
        case .openaiResponses, .compatibleGateway, .anthropic, .deepseekResponses:
            return true
        case .applePCC, .appleOnDevice, .localResponses:
            return false
        }
    }

    public func selectedReasoningValue(for model: CatalogModelChoice, kind: ProviderKind) -> String {
        if let values = model.effortValues, !values.isEmpty {
            let current: String
            switch kind {
            case .openaiResponses, .compatibleGateway:
                current = effortWireValue(openaiEffort)
            case .deepseekResponses:
                current = effortWireValue(deepseekEffort)
            case .anthropic:
                current = anthropicEffort ?? effortWireValue(anthropicThinking)
            case .applePCC, .appleOnDevice, .localResponses:
                return values[0]
            }
            return values.contains(current) ? current : values[0]
        }
        if let values = model.thinkingValues, !values.isEmpty {
            let current: String
            switch anthropicThinking {
            case .thinkingDisabled, .disabled, .serviceDefault: current = "disabled"
            case .thinkingAdaptive: current = values.contains("adaptive") ? "adaptive" : values[0]
            case .thinkingBudgetTokens: current = values.contains("enabled") ? "enabled" : values[0]
            case .effort(let value): current = value
            }
            return values.contains(current) ? current : values[0]
        }
        return intensity(for: kind).label
    }

    public mutating func applyCatalogReasoning(_ value: String, model: CatalogModelChoice, kind: ProviderKind) {
        if let values = model.effortValues, values.contains(value) {
            let choice: ReasoningChoice = (value == "none" || value == "off") ? .disabled : .effort(value)
            switch kind {
            case .openaiResponses, .compatibleGateway:
                openaiEffort = choice
            case .deepseekResponses:
                deepseekEffort = choice
            case .anthropic:
                anthropicEffort = value
                if value == "none" || value == "off" || value == "disabled" {
                    anthropicThinking = .thinkingDisabled
                    anthropicEffort = nil
                } else {
                    anthropicThinking = .thinkingAdaptive
                }
            case .applePCC, .appleOnDevice, .localResponses:
                break
            }
            return
        }
        if model.thinkingValues?.contains(value) == true {
            switch value {
            case "disabled", "none", "off":
                anthropicThinking = .thinkingDisabled
            case "adaptive":
                anthropicThinking = .thinkingAdaptive
            case "enabled":
                let budget = model.tokenBudgetMinimum ?? 1_024
                anthropicThinking = .thinkingBudgetTokens(max(budget, 1_024))
            default:
                anthropicThinking = .thinkingAdaptive
            }
        }
    }

    private func effortWireValue(_ choice: ReasoningChoice) -> String {
        switch choice {
        case .serviceDefault: "medium"
        case .disabled, .thinkingDisabled: "none"
        case .effort(let value): value
        case .thinkingAdaptive: "adaptive"
        case .thinkingBudgetTokens: "enabled"
        }
    }

    public func intensity(for kind: ProviderKind) -> ReasoningIntensity {
        switch kind {
        case .openaiResponses, .compatibleGateway:
            switch openaiEffort {
            case .disabled: .off
            case .effort("low"): .low
            case .effort("medium"): .medium
            case .effort("high"): .high
            case .effort("xhigh"), .effort("max"): .max
            default: .medium
            }
        case .anthropic:
            switch anthropicThinking {
            case .thinkingDisabled: .off
            case .thinkingBudgetTokens(let tokens) where tokens < 4_000: .low
            case .thinkingBudgetTokens(let tokens) where tokens < 8_000: .medium
            default: .high
            }
        case .deepseekResponses:
            switch deepseekEffort {
            case .disabled: .off
            case .effort("max"): .max
            default: .high
            }
        case .applePCC, .appleOnDevice, .localResponses:
            .off
        }
    }

    public mutating func setIntensity(_ intensity: ReasoningIntensity, for kind: ProviderKind) {
        switch kind {
        case .openaiResponses, .compatibleGateway:
            openaiEffort = {
                switch intensity {
                case .off: .disabled
                case .low: .effort("low")
                case .medium: .effort("medium")
                case .high: .effort("high")
                case .max: .effort("xhigh")
                }
            }()
        case .anthropic:
            anthropicThinking = intensity == .off ? .thinkingDisabled : .thinkingAdaptive
        case .deepseekResponses:
            deepseekEffort = {
                switch intensity {
                case .off: .disabled
                case .max: .effort("max")
                case .low, .medium, .high: .effort("high")
                }
            }()
        case .applePCC, .appleOnDevice, .localResponses:
            break
        }
    }
}

public enum ReasoningPresentation: Equatable, Sendable {
    case none
    case notAdjustable
    case unknown
    case openaiEffort
    case anthropicThinking
    case deepseekEffort
}

public enum ReasoningCapabilityMapper {
    public static func presentation(
        kind: ProviderKind,
        reasoning: ModelCatalogSupport?,
        configurable: ModelCatalogSupport?,
        controls: [ModelReasoningControlDescriptor]
    ) -> ReasoningPresentation {
        switch kind {
        case .applePCC, .appleOnDevice:
            return .none
        case .localResponses:
            return .none
        case .openaiResponses, .compatibleGateway:
            if reasoning == .unsupported { return .none }
            if !controls.isEmpty || configurable == .supported { return .openaiEffort }
            if reasoning == .supported, configurable == .unsupported { return .notAdjustable }
            return .unknown
        case .anthropic:
            if reasoning == .unsupported { return .none }
            return .anthropicThinking
        case .deepseekResponses:
            return .deepseekEffort
        }
    }
}
