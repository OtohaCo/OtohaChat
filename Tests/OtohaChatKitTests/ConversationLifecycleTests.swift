import AgentCore
import AgentModels
import AgentTools
import AgentUsage
import OtohaChatKit
import Foundation
import Testing

struct ConversationLifecycleTests {
    @Test func fixtureChatUsesStableIdentitiesAndDrainsAfterStop() async throws {
        let controller = try makeFixtureConversationController(pacing: .immediate)
        let first = try await sendAndWait(controller, "hello there")
        #expect(first.items.contains { if case .user = $0 { return true }; return false })
        let ids = first.items.map(\.id)
        #expect(Set(ids).count == ids.count)

        let second = try await sendAndWait(controller, "follow up")
        let laterIDs = second.items.map(\.id)
        #expect(Set(laterIDs).count == laterIDs.count)
        #expect(second.phase == .idle)

        try await controller.send(ConversationStartRequest(text: "slow"))
        await controller.stop()
        let stopped = await controller.snapshot()
        #expect(stopped.phase == .idle)

        let resumed = try await sendAndWait(controller, "after stop")
        #expect(resumed.phase == .idle)
        #expect(resumed.items.contains { if case .user(let message) = $0 { return message.text == "after stop" }; return false })
    }

    @Test func calculatorToolLoopCompletes() async throws {
        let controller = try makeFixtureConversationController(pacing: .immediate)
        let snapshot = try await sendAndWait(controller, "Please compute 2+2 with calculator")
        #expect(snapshot.items.contains { if case .tool(let call) = $0 { return call.name == CalculatorTool.name }; return false })
        #expect(snapshot.phase == .idle)
    }

    @Test func failedRunExposesTypedReasonAndMarksProposedTools() {
        var projection = ConversationProjection(conversationID: UUID())
        projection.beginUserTurn("1+2", generation: 1)
        projection.apply(.model(.toolCallStarted(.init(rawValue: "toolu-1"), name: CalculatorTool.name)))
        projection.setTerminal(.failed(.toolRegistry(.invalidJSON)))
        #expect(projection.snapshot.runFailureText == "The model produced tool arguments that are not valid JSON.")
        let tool = projection.snapshot.items.compactMap { item -> DisplayToolCall? in
            if case .tool(let call) = item { return call }
            return nil
        }.first
        #expect(tool?.state == .failed)
        #expect(tool?.name == CalculatorTool.name)
    }

    @Test func appleInvalidRequestExplainsHowToContinue() {
        let error = ModelProviderError(
            kind: .invalidRequest,
            message: "Apple model generation failed (invalidRequest)."
        )
        #expect(RunFailureText.describe(error).contains("new chat"))
        #expect(RunFailureText.describe(.provider(error)).contains("previous turn"))
    }

    @Test func completedToolStaysCompletedWhenTheRunFails() {
        var projection = ConversationProjection(conversationID: UUID())
        projection.beginUserTurn("1+2", generation: 1)
        projection.apply(.model(.toolCallStarted(.init(rawValue: "toolu-1"), name: CalculatorTool.name)))
        projection.apply(.toolCompleted(.init(
            callID: .init(rawValue: "toolu-1"),
            content: [.text("3")],
            isError: false
        )))
        projection.setTerminal(.failed(.provider(.init(
            kind: .invalidResponse,
            message: "Fixture protocol failure after tool."
        ))))
        let tool = projection.snapshot.items.compactMap { item -> DisplayToolCall? in
            if case .tool(let call) = item { return call }
            return nil
        }.first
        #expect(tool?.state == .completed)
        #expect(tool?.isError == false)
        #expect(projection.snapshot.runFailureText != nil)
    }

    @Test func executionReportKeepsToolCompletionWhenLaterProviderFails() async throws {
        let controller = try makeFixtureConversationController(pacing: .immediate)
        let snapshot = try await sendAndWait(controller, "Please compute 2+2 with calculator, then fail after tool")
        let report = try #require(snapshot.executionReport)
        #expect(snapshot.terminal == .failed(.provider(.init(
            kind: .invalidResponse,
            message: "Fixture protocol failure after tool."
        ))))
        #expect(report.toolObservations.contains {
            $0.name == CalculatorTool.name && $0.status == .completed(isError: false)
        })
        #expect(report.presentation == .malformed(reason: "final response unavailable"))
        #expect(report.coverage.isComplete)
        #expect(ExecutionReportCopy.message(for: report) == "A tool completed, but the final reply was unavailable.")
        let tool = snapshot.items.compactMap { item -> DisplayToolCall? in
            if case .tool(let call) = item { return call }
            return nil
        }.first
        #expect(tool?.state == .completed)
    }

    @Test func executionReportUsesRunSessionIdentityInsteadOfConversationIdentity() async throws {
        let conversationID = UUID()
        let sessionID = UUID()
        let controller = try makeFixtureConversationController(
            conversationID: conversationID,
            sessionID: sessionID,
            pacing: .immediate
        )
        let snapshot = try await sendAndWait(controller, "hello there")
        let report = try #require(snapshot.executionReport)
        #expect(report.sessionID == sessionID)
        #expect(report.sessionID != conversationID)
        #expect(report.coverage.isComplete)
    }

    @Test func usageDoesNotTreatCacheAsExtraTotal() {
        var accumulator = UsageAccumulator()
        let identity = UsageRecordIdentity(
            source: .modelResponse,
            sessionID: UUID(),
            runID: UUID(),
            invocationID: "one",
            providerResponseID: "r1",
            model: .init(provider: "openai", name: "gpt-test")
        )
        _ = accumulator.record(.init(
            identity: identity,
            usage: .init(inputTokens: 10, outputTokens: 4, cachedInputTokens: 3, reasoningTokens: 2),
            status: .finalized
        ))
        let summary = accumulator.summary(identity: identity)
        #expect(summary.reportedUsage.inputTokens == 10)
        #expect(summary.reportedUsage.outputTokens == 4)
        #expect(summary.reportedUsage.cachedInputTokens == 3)
        #expect(summary.totalTokens == 14)
    }
}

private func sendAndWait(_ controller: ConversationController, _ text: String) async throws -> ConversationSnapshot {
    try await controller.send(ConversationStartRequest(text: text))
    for _ in 0..<400 {
        let snapshot = await controller.snapshot()
        if snapshot.phase == .idle, snapshot.generation > 0 { return snapshot }
        try await Task.sleep(for: .milliseconds(10))
    }
    return await controller.snapshot()
}
