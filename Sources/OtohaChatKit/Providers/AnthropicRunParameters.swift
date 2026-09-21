import AgentProviders
import Foundation

/// Wire thinking and effort for one Anthropic Messages request.
///
/// Catalog rows are per-model. Sonnet 4.5 only accepts extended thinking
/// (`enabled` + `budget_tokens`) and rejects `adaptive` and `output_config.effort`.
/// Sonnet 5 and later reject `enabled`. Leftover profile reasoning from another
/// Claude model must not be forwarded unchanged.
public struct AnthropicRunParameters: Equatable, Sendable {
    public var thinking: AnthropicThinking
    public var effort: AnthropicEffort?

    public static func resolve(
        reasoning: ReasoningConfiguration,
        model: CatalogModelChoice?,
        maximumOutputTokens: Int
    ) -> AnthropicRunParameters {
        let allowsAdaptive = model?.supportsAnthropicAdaptiveThinking ?? false
        let allowsEnabled = model?.supportsAnthropicEnabledThinking ?? false
        let effort = allowedEffort(reasoning.anthropicEffort, model: model)

        switch reasoning.anthropicThinking {
        case .thinkingAdaptive:
            if model == nil {
                return AnthropicRunParameters(thinking: .adaptive, effort: nil)
            }
            if allowsAdaptive {
                return AnthropicRunParameters(thinking: .adaptive, effort: effort)
            }
            if allowsEnabled {
                return AnthropicRunParameters(thinking: enabledBudget(reasoning, maximumOutputTokens), effort: nil)
            }
            return AnthropicRunParameters(thinking: .disabled, effort: nil)

        case .thinkingBudgetTokens(let tokens):
            if model == nil {
                return AnthropicRunParameters(
                    thinking: clampedBudget(tokens, maximumOutputTokens: maximumOutputTokens),
                    effort: nil
                )
            }
            if allowsEnabled {
                return AnthropicRunParameters(
                    thinking: clampedBudget(tokens, maximumOutputTokens: maximumOutputTokens),
                    effort: allowsAdaptive ? effort : nil
                )
            }
            if allowsAdaptive {
                return AnthropicRunParameters(thinking: .adaptive, effort: effort)
            }
            return AnthropicRunParameters(thinking: .disabled, effort: nil)

        case .thinkingDisabled, .disabled, .serviceDefault, .effort:
            // Thinking off wins. Leftover effort must not become adaptive.
            return AnthropicRunParameters(thinking: .disabled, effort: nil)
        }
    }

    private static func allowedEffort(_ raw: String?, model: CatalogModelChoice?) -> AnthropicEffort? {
        guard let model, let raw, model.anthropicEffortWireValues.contains(raw) else { return nil }
        let value = raw.lowercased()
        guard value != "none", value != "off", value != "disabled" else { return nil }
        return AnthropicEffort(rawValue: raw)
    }

    private static func enabledBudget(
        _ reasoning: ReasoningConfiguration,
        _ maximumOutputTokens: Int
    ) -> AnthropicThinking {
        let requested: Int
        if case .thinkingBudgetTokens(let tokens) = reasoning.anthropicThinking {
            requested = tokens
        } else {
            requested = 1_024
        }
        return clampedBudget(requested, maximumOutputTokens: maximumOutputTokens)
    }

    private static func clampedBudget(_ tokens: Int, maximumOutputTokens: Int) -> AnthropicThinking {
        let ceiling = max(maximumOutputTokens - 1, 1_024)
        return .enabled(budgetTokens: min(max(tokens, 1_024), ceiling))
    }
}
