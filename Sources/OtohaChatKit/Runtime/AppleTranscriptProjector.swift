import AgentCore
import AgentModels
import Foundation

/// Apple's native session rejects a transcript that is not strictly alternating.
/// SwiftAgent keeps a failed user turn in canonical history and does not append
/// an empty assistant message, so the next send becomes `user, user`.
///
/// This projector repairs only the request the Apple model sees. Canonical
/// session history is unchanged.
public struct AppleTranscriptProjector: AgentContextProjector {
    public static let missingReplyText = "No reply was produced for the previous turn."

    private let base: any AgentContextProjector

    public init(base: any AgentContextProjector = AgentIdentityContextProjector()) {
        self.base = base
    }

    public func project(_ input: AgentContextProjectionInput) async throws -> AgentContextProjection {
        let projected = try await base.project(input)
        let repaired = Self.repair(projected.messages)
        guard repaired != projected.messages else { return projected }
        return AgentContextProjection(
            messages: repaired,
            plan: AgentContextProjectionPlan(
                projectionID: "apple-transcript",
                version: "1",
                sourceRevision: projected.plan.sourceRevision,
                sourceDigest: projected.plan.sourceDigest,
                contextEpoch: projected.plan.contextEpoch,
                lossy: true,
                reason: "Missing Apple assistant turns were filled so the next user message can be sent."
            )
        )
    }

    public static func repair(_ messages: [ModelMessage]) -> [ModelMessage] {
        let visible = messages.filter { message in
            guard case .assistant(let content, let calls) = message else { return true }
            if !calls.isEmpty { return true }
            return content.contains(where: hasVisibleContent)
        }

        var repaired: [ModelMessage] = []
        var lastVisibleRole: ModelRole?
        for message in visible {
            if message.role == .user, lastVisibleRole == .user {
                repaired.append(stubAssistant)
                lastVisibleRole = .assistant
            }
            repaired.append(message)
            if message.role != .system && message.role != .developer {
                lastVisibleRole = message.role
            }
        }
        return repaired
    }

    private static var stubAssistant: ModelMessage {
        .assistant(content: [.text(missingReplyText)], toolCalls: [])
    }

    private static func hasVisibleContent(_ part: ModelContent) -> Bool {
        switch part {
        case .text(let text):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .json, .reasoning, .providerContinuation:
            true
        }
    }
}
