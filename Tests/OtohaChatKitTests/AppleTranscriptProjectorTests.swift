import AgentCore
import AgentModels
import OtohaChatKit
import Foundation
import Testing

struct AppleTranscriptProjectorTests {
    @Test func consecutiveUserTurnsGetAStubAssistant() async throws {
        let canonical: [ModelMessage] = [
            .system("You are OtohaChat."),
            .user([.text("Hello, Apple")]),
            .user([.text("hello, Mac")]),
        ]
        let projection = try await AppleTranscriptProjector().project(input(canonical))
        #expect(projection.messages == [
            .system("You are OtohaChat."),
            .user([.text("Hello, Apple")]),
            .assistant(content: [.text(AppleTranscriptProjector.missingReplyText)], toolCalls: []),
            .user([.text("hello, Mac")]),
        ])
        #expect(projection.plan.lossy)
        #expect(projection.plan.sourceDigest == (try AgentContextProjectionSource.digest(messages: canonical)))
        #expect(projection.plan.sourceRevision == 3)
    }

    @Test func aSingleUserTurnIsUnchanged() async throws {
        let canonical: [ModelMessage] = [.user([.text("hello")])]
        let projection = try await AppleTranscriptProjector().project(input(canonical))
        #expect(projection.messages == canonical)
        #expect(!projection.plan.lossy)
        #expect(projection.plan.projectionID == "identity")
    }

    @Test func emptyAssistantTurnsAreDroppedThenRepaired() {
        let repaired = AppleTranscriptProjector.repair([
            .user([.text("first")]),
            .assistant(content: [.text("   ")], toolCalls: []),
            .user([.text("second")]),
        ])
        #expect(repaired == [
            .user([.text("first")]),
            .assistant(content: [.text(AppleTranscriptProjector.missingReplyText)], toolCalls: []),
            .user([.text("second")]),
        ])
    }

    @Test func toolPairsStayAdjacent() {
        let call = ToolCall(id: .init(rawValue: "call-1"), name: "calculator", argumentsJSON: #"{"expression":"1+1"}"#)
        let repaired = AppleTranscriptProjector.repair([
            .user([.text("1+1")]),
            .assistant(content: [], toolCalls: [call]),
            .tool(.init(callID: call.id, content: [.text("2")], isError: false)),
            .user([.text("thanks")]),
        ])
        #expect(repaired.count == 4)
        guard case .assistant(_, let calls) = repaired[1] else {
            Issue.record("expected assistant tool proposal")
            return
        }
        #expect(calls.map(\.id) == [call.id])
        guard case .tool(let result) = repaired[2] else {
            Issue.record("expected tool result")
            return
        }
        #expect(result.callID == call.id)
    }

    @Test func semanticHandoffStillStripsOpaqueReasoning() async throws {
        let canonical: [ModelMessage] = [
            .user([.text("hi")]),
            .assistant(
                content: [.reasoning("private"), .text("hello")],
                toolCalls: []
            ),
            .user([.text("again")]),
        ]
        let projection = try await AppleTranscriptProjector(base: AgentSemanticHandoffProjector())
            .project(input(canonical))
        #expect(projection.messages == [
            .user([.text("hi")]),
            .assistant(content: [.text("hello")], toolCalls: []),
            .user([.text("again")]),
        ])
    }

    @Test func appleOutputTokensAreCappedBelowTheCloudDefault() {
        #expect(AppleGenerationLimits.responseTokens(requested: 4_096) == 1_024)
        #expect(AppleGenerationLimits.responseTokens(requested: 512) == 512)
        #expect(AppleGenerationLimits.responseTokens(requested: 0) == 1)
    }
}

private func input(_ messages: [ModelMessage]) -> AgentContextProjectionInput {
    AgentContextProjectionInput(
        canonicalMessages: messages,
        model: ModelID(provider: "apple-foundation", name: "private-cloud-compute"),
        sessionID: UUID(),
        runID: UUID(),
        conversationRevision: 3,
        contextEpoch: 0,
        modelTurn: 1
    )
}
