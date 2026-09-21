import AgentCore
import AgentModels
import Foundation

public enum HandoffPlan: Equatable, Sendable {
    case identity
    case semantic(warning: String)
    case rejected(String)

    public var warning: String? {
        if case .semantic(let warning) = self { return warning }
        return nil
    }
}

public enum HandoffPolicy {
    public static func plan(
        from previous: PreparedProvider?,
        to next: PreparedProvider
    ) -> HandoffPlan {
        guard let previous else { return .identity }
        if previous.model == next.model,
           previous.deployment == next.deployment,
           previous.profile.id == next.profile.id
        {
            return .identity
        }
        if previous.model.provider != next.model.provider
            || previous.deployment.apiDialect != next.deployment.apiDialect
        {
            return .semantic(
                warning: "Switching from \(previous.model.provider)/\(previous.model.name) to \(next.model.provider)/\(next.model.name) uses a semantic handoff. Opaque reasoning and provider continuation are not carried over. This is not a lossless transfer."
            )
        }
        if previous.model.name != next.model.name {
            return .semantic(
                warning: "The next message uses \(next.model.name). History stays on this session, but provider continuation for \(previous.model.name) is not reused."
            )
        }
        return .identity
    }

    public static func projector(for plan: HandoffPlan) -> any AgentContextProjector {
        switch plan {
        case .identity, .rejected: AgentIdentityContextProjector()
        case .semantic: AgentSemanticHandoffProjector()
        }
    }
}
