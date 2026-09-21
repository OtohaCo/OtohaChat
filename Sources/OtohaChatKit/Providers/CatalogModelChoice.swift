import AgentCatalog
import Foundation

/// A host-facing catalog row. Identity and capabilities come from SwiftAgent's
/// `ModelCatalogEntry`; the app does not invent tools, reasoning, or token limits
/// from a model name.
public struct CatalogModelChoice: Equatable, Sendable, Codable, Identifiable {
    public var id: String { modelName }
    public var modelName: String
    public var displayName: String?
    public var source: String
    public var reasoning: String
    public var configurableReasoning: String
    public var tools: String
    public var structuredOutput: String
    public var multiTurn: String
    public var effortValues: [String]?
    public var thinkingValues: [String]?
    public var tokenBudgetMinimum: Int?
    public var tokenBudgetMaximum: Int?
    public var maximumInputTokens: Int?
    public var maximumOutputTokens: Int?
    public var usedHostManifest: Bool

    public init(
        modelName: String,
        displayName: String? = nil,
        source: String,
        reasoning: String = ModelCatalogSupport.unknown.rawValue,
        configurableReasoning: String = ModelCatalogSupport.unknown.rawValue,
        tools: String = ModelCatalogSupport.unknown.rawValue,
        structuredOutput: String = ModelCatalogSupport.unknown.rawValue,
        multiTurn: String = ModelCatalogSupport.unknown.rawValue,
        effortValues: [String]? = nil,
        thinkingValues: [String]? = nil,
        tokenBudgetMinimum: Int? = nil,
        tokenBudgetMaximum: Int? = nil,
        maximumInputTokens: Int? = nil,
        maximumOutputTokens: Int? = nil,
        usedHostManifest: Bool = false
    ) {
        self.modelName = modelName
        self.displayName = displayName
        self.source = source
        self.reasoning = reasoning
        self.configurableReasoning = configurableReasoning
        self.tools = tools
        self.structuredOutput = structuredOutput
        self.multiTurn = multiTurn
        self.effortValues = effortValues
        self.thinkingValues = thinkingValues
        self.tokenBudgetMinimum = tokenBudgetMinimum
        self.tokenBudgetMaximum = tokenBudgetMaximum
        self.maximumInputTokens = maximumInputTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.usedHostManifest = usedHostManifest
    }

    public init(entry: ModelCatalogEntry) {
        let effort = Self.control(entry.reasoningControls, kind: .effort)
        let thinking = Self.control(entry.reasoningControls, kind: .thinkingMode)
        let budget = Self.control(entry.reasoningControls, kind: .tokenBudget)
        self.init(
            modelName: entry.model.name,
            displayName: entry.displayName,
            source: entry.sources.first.map(\.kind.rawValue) ?? ModelCatalogSourceKind.upstreamAPI.rawValue,
            reasoning: entry.capabilities.reasoning.rawValue,
            configurableReasoning: entry.capabilities.configurableReasoning.rawValue,
            tools: entry.capabilities.tools.rawValue,
            structuredOutput: entry.capabilities.structuredOutput.rawValue,
            multiTurn: entry.capabilities.multiTurn.rawValue,
            effortValues: effort?.allowedValues,
            thinkingValues: thinking?.allowedValues,
            tokenBudgetMinimum: budget?.integerRange?.minimum,
            tokenBudgetMaximum: budget?.integerRange?.maximum,
            maximumInputTokens: entry.maximumInputTokens,
            maximumOutputTokens: entry.maximumOutputTokens,
            usedHostManifest: entry.sources.contains(where: { $0.kind == .documentedContract })
        )
    }

    public var title: String { displayName ?? modelName }

    public var reasoningSupport: ModelCatalogSupport { .init(rawValue: reasoning) }
    public var configurableReasoningSupport: ModelCatalogSupport { .init(rawValue: configurableReasoning) }
    public var toolsSupport: ModelCatalogSupport { .init(rawValue: tools) }

    public var hasAdjustableReasoning: Bool {
        configurableReasoningSupport == .supported
            && (!(effortValues ?? []).isEmpty || !(thinkingValues ?? []).isEmpty || tokenBudgetMaximum != nil)
    }

    public var parameterSummary: String {
        var parts: [String] = []
        if reasoningSupport == .supported { parts.append("Reasoning") }
        if hasAdjustableReasoning { parts.append("Adjustable") }
        if toolsSupport == .supported { parts.append("Tools") }
        if let maximumInputTokens { parts.append("In \(Self.compactTokens(maximumInputTokens))") }
        if let maximumOutputTokens { parts.append("Out \(Self.compactTokens(maximumOutputTokens))") }
        return parts.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case modelName, displayName, source
        case reasoning, configurableReasoning, tools, structuredOutput, multiTurn
        case effortValues, thinkingValues
        case tokenBudgetMinimum, tokenBudgetMaximum
        case maximumInputTokens, maximumOutputTokens
        case usedHostManifest
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelName = try container.decode(String.self, forKey: .modelName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ModelCatalogSourceKind.upstreamAPI.rawValue
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ModelCatalogSupport.unknown.rawValue
        configurableReasoning = try container.decodeIfPresent(String.self, forKey: .configurableReasoning)
            ?? ModelCatalogSupport.unknown.rawValue
        tools = try container.decodeIfPresent(String.self, forKey: .tools) ?? ModelCatalogSupport.unknown.rawValue
        structuredOutput = try container.decodeIfPresent(String.self, forKey: .structuredOutput)
            ?? ModelCatalogSupport.unknown.rawValue
        multiTurn = try container.decodeIfPresent(String.self, forKey: .multiTurn) ?? ModelCatalogSupport.unknown.rawValue
        effortValues = try container.decodeIfPresent([String].self, forKey: .effortValues)
        thinkingValues = try container.decodeIfPresent([String].self, forKey: .thinkingValues)
        tokenBudgetMinimum = try container.decodeIfPresent(Int.self, forKey: .tokenBudgetMinimum)
        tokenBudgetMaximum = try container.decodeIfPresent(Int.self, forKey: .tokenBudgetMaximum)
        maximumInputTokens = try container.decodeIfPresent(Int.self, forKey: .maximumInputTokens)
        maximumOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maximumOutputTokens)
        usedHostManifest = try container.decodeIfPresent(Bool.self, forKey: .usedHostManifest) ?? false
    }

    private static func control(
        _ controls: [ModelReasoningControlDescriptor],
        kind: ModelReasoningControlKind
    ) -> ModelReasoningControlDescriptor? {
        controls.first { $0.kind == kind && $0.support == .supported }
    }

    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return "\(value / 1_000)k" }
        return "\(value)"
    }
}
