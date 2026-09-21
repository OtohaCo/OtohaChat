import AgentCore
import AgentModels
import AgentTools
import AgentUsage
import Foundation

/// Single consumer of `AgentRun.events`. Adapted from SwiftAgent Examples/AppleChatApp.
public actor ConversationController {
    public nonisolated let conversationID: UUID
    public nonisolated let snapshots: AsyncStream<ConversationSnapshot>

    private let session: any ConversationSessionHandle
    private let mailbox: ConversationSnapshotMailbox
    private let eventDeliveryHook: @Sendable (AgentEvent) async -> Void
    private var projection: ConversationProjection
    private var generation: UInt64 = 0
    private var startupTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var activeRun: ConversationRunHandle?
    private var abandonedCleanups: [UUID: Task<Void, Never>] = [:]
    private var usageAccumulator = UsageAccumulator()
    private var usageRunInfo: AgentRunInfo?
    private var usageTurn = 0
    private var usageResponseInfo: ResponseInfo?
    private var usageDiagnosticCount = 0
    private var executionReportReducer: ExecutionReportReducer?

    public init(
        conversationID: UUID = UUID(),
        session: any ConversationSessionHandle,
        maxDisplayItems: Int = 400
    ) {
        self.init(
            conversationID: conversationID,
            session: session,
            maxDisplayItems: maxDisplayItems,
            eventDeliveryHook: { _ in }
        )
    }

    init(
        conversationID: UUID = UUID(),
        session: any ConversationSessionHandle,
        maxDisplayItems: Int = 400,
        eventDeliveryHook: @escaping @Sendable (AgentEvent) async -> Void
    ) {
        self.conversationID = conversationID
        self.session = session
        self.eventDeliveryHook = eventDeliveryHook
        let projection = ConversationProjection(conversationID: conversationID, maxItems: maxDisplayItems)
        self.projection = projection
        let mailbox = ConversationSnapshotMailbox(initial: projection.snapshot)
        self.mailbox = mailbox
        snapshots = mailbox.snapshots
    }

    deinit {
        startupTask?.cancel()
        observationTask?.cancel()
        cleanupTask?.cancel()
        abandonedCleanups.values.forEach { $0.cancel() }
        mailbox.finish()
    }

    public func restoreDisplayItems(_ items: [ConversationItem]) {
        projection.restoreItems(items)
        publish()
    }

    public func setPendingConfigurationNote(_ note: String?) {
        projection.setPendingConfigurationNote(note)
        publish()
    }

    @discardableResult
    public func send(_ request: ConversationStartRequest) throws -> UInt64 {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ConversationControllerError.emptyInput }
        guard projection.snapshot.phase == .idle else { throw ConversationControllerError.runInProgress }

        generation &+= 1
        let reservedGeneration = generation
        let visible = (request.displayText ?? request.text).trimmingCharacters(in: .whitespacesAndNewlines)
        projection.beginUserTurn(visible, generation: reservedGeneration)
        if let warning = request.handoffWarning {
            projection.setHandoffWarning(warning)
        }
        publish()

        let session = self.session
        startupTask = Task { [weak self] in
            do {
                let run = try await session.start(request)
                await self?.attach(run, generation: reservedGeneration)
            } catch {
                await self?.startupFailed(error, generation: reservedGeneration)
            }
        }
        return reservedGeneration
    }

    /// Cancel the active Run and wait until it has physically drained.
    public func stop() async {
        guard projection.snapshot.phase != .idle else { return }
        projection.setPhase(.stopRequested)
        publish()
        startupTask?.cancel()
        if let activeRun { await activeRun.cancel() }
        if let cleanupTask {
            _ = await cleanupTask.result
        } else if startupTask != nil {
            // Startup cancelled before attach; wait for startupFailed to publish idle.
            while projection.snapshot.phase != .idle {
                await Task.yield()
            }
        }
    }

    public func snapshot() -> ConversationSnapshot {
        projection.snapshot
    }

    public func canonicalSnapshot() async -> AgentConversationSnapshot {
        await session.conversationSnapshot()
    }

    private func attach(_ run: ConversationRunHandle, generation: UInt64) async {
        guard generation == self.generation else {
            retainAbandonedCleanup(for: run)
            return
        }

        startupTask = nil
        activeRun = run
        executionReportReducer = .init(sessionID: run.sessionID, runID: run.id)
        let stopWasRequested = projection.snapshot.phase == .stopRequested
        projection.setPhase(stopWasRequested ? .stopRequested : .running)
        publish()

        let events = run.events
        let eventDeliveryHook = self.eventDeliveryHook
        let observationTask = Task { [weak self] in
            for await event in events {
                await eventDeliveryHook(event)
                await self?.receive(event, generation: generation, runID: run.id)
            }
            await self?.observationEnded(generation: generation, runID: run.id)
        }
        self.observationTask = observationTask
        cleanupTask = Task { [weak self] in
            let result: Result<ConversationRunResult, Error>
            do {
                result = .success(try await run.wait())
            } catch {
                result = .failure(error)
            }
            await self?.logicalCompletion(result, generation: generation, runID: run.id)
            do {
                try await run.waitForDrain()
            } catch is CancellationError {
                return
            } catch {
                await self?.logicalCompletion(.failure(error), generation: generation, runID: run.id)
            }
            _ = await observationTask.result
            await self?.drainCompleted(generation: generation, runID: run.id)
        }

        if stopWasRequested { await run.cancel() }
    }

    private func startupFailed(_ error: any Error, generation: UInt64) {
        guard generation == self.generation else { return }
        startupTask = nil
        if error is CancellationError, projection.snapshot.phase == .stopRequested {
            projection.setTerminal(.cancelled)
        } else {
            projection.setTerminal(.failed(Self.agentFailure(error)))
            projection.setRunFailureText(RunFailureText.describe(error))
        }
        projection.clearRunAfterDrain()
        publish()
    }

    private func receive(_ event: AgentEvent, generation: UInt64, runID: UUID) {
        guard generation == self.generation, activeRun?.id == runID else { return }
        executionReportReducer?.consume(event)
        if case .runFinished(.failed) = event, let report = executionReportReducer?.report,
           report.finalModelText?.isEmpty != false
        {
            executionReportReducer?.recordPresentation(.malformed(reason: "final response unavailable"))
        }
        projection.apply(event)
        projection.updateExecutionReport(executionReportReducer?.report)
        recordUsage(event)
        publish()
    }

    private func observationEnded(generation: UInt64, runID: UUID) {
        guard generation == self.generation, activeRun?.id == runID else { return }
        executionReportReducer?.markStreamEnded()
        projection.updateExecutionReport(executionReportReducer?.report)
        publish()
    }

    private func recordUsage(_ event: AgentEvent) {
        switch event {
        case .runStarted(let info):
            usageRunInfo = info
            usageTurn = 0
            usageResponseInfo = nil
        case .turnStarted(let number):
            usageTurn = number
            usageResponseInfo = nil
        case .model(.responseStarted(let info)):
            usageResponseInfo = info
            recordUsage(.init(), status: .provisional, info: info)
        case .model(.usage(let usage)):
            guard let usageResponseInfo else { return }
            recordUsage(usage, status: .provisional, info: usageResponseInfo)
        case .model(.responseCompleted(let response)):
            usageResponseInfo = response.info
            recordUsage(response.usage, status: .finalized, info: response.info)
        default:
            break
        }
    }

    private func recordUsage(
        _ usage: ModelUsage,
        status: UsageObservationStatus,
        info: ResponseInfo
    ) {
        guard let runInfo = usageRunInfo else { return }
        let identity = UsageRecordIdentity(
            source: .modelResponse,
            sessionID: runInfo.sessionID,
            runID: runInfo.runID,
            invocationID: "\(runInfo.runID.uuidString):turn-\(usageTurn)",
            providerResponseID: info.id,
            model: info.model
        )
        let result = usageAccumulator.record(.init(identity: identity, usage: usage, status: status))
        if result.diagnostic != nil { usageDiagnosticCount += 1 }
        projection.updateUsage(
            response: usageAccumulator.summary(identity: identity),
            run: usageAccumulator.summary(sessionID: runInfo.sessionID, runID: runInfo.runID),
            session: usageAccumulator.summary(sessionID: runInfo.sessionID),
            diagnosticCount: usageDiagnosticCount
        )
    }

    private func logicalCompletion(
        _ result: Result<ConversationRunResult, Error>,
        generation: UInt64,
        runID: UUID
    ) {
        guard generation == self.generation, activeRun?.id == runID else { return }
        switch result {
        case .success(let result):
            executionReportReducer?.recordWait(outcome: .success(Self.outcome(from: result)))
            switch result {
            case .completed: projection.setTerminal(.completed)
            case .refused: projection.setTerminal(.refused)
            case .incomplete(let reason):
                if let report = executionReportReducer?.report,
                   case .failed = report.runtimeTermination,
                   report.finalModelText?.isEmpty != false
                {
                    executionReportReducer?.recordPresentation(
                        .malformed(reason: "final response unavailable")
                    )
                }
                projection.setTerminal(.incomplete(reason))
            }
        case .failure(let error):
            let failure = Self.agentFailure(error)
            executionReportReducer?.recordWait(outcome: .failure(failure))
            if executionReportReducer?.report.finalModelText?.isEmpty != false {
                executionReportReducer?.recordPresentation(
                    .malformed(reason: "final response unavailable")
                )
            }
            if error is CancellationError {
                projection.setTerminal(.cancelled)
            } else {
                projection.setTerminal(.failed(failure))
                projection.setRunFailureText(RunFailureText.describe(error))
            }
        }
        projection.updateExecutionReport(executionReportReducer?.report)
        projection.setPhase(.draining)
        publish()
    }

    private func drainCompleted(generation: UInt64, runID: UUID) {
        guard generation == self.generation, activeRun?.id == runID else { return }
        executionReportReducer?.markDrainCompleted()
        projection.updateExecutionReport(executionReportReducer?.report)
        observationTask?.cancel()
        observationTask = nil
        cleanupTask = nil
        activeRun = nil
        projection.clearRunAfterDrain()
        publish()
    }

    private func retainAbandonedCleanup(for run: ConversationRunHandle) {
        let events = run.events
        let task = Task { [weak self] in
            let observation = Task {
                for await _ in events {}
            }
            await run.cancel()
            _ = try? await run.wait()
            _ = try? await run.waitForDrain()
            _ = await observation.result
            await self?.abandonedCleanupFinished(run.id)
        }
        abandonedCleanups[run.id] = task
    }

    private func abandonedCleanupFinished(_ runID: UUID) {
        abandonedCleanups.removeValue(forKey: runID)
    }

    private func publish() {
        mailbox.send(projection.snapshot)
    }

    private static func agentFailure(_ error: any Error) -> AgentFailure {
        switch error {
        case is CancellationError: .cancelled
        case let value as AgentLoopError: .loop(value)
        case let value as AgentSessionError: .session(value)
        case let value as ModelProviderError: .provider(value)
        case let value as ModelStreamError: .modelStream(value)
        case let value as ToolRegistryError: .toolRegistry(value)
        case let value as ToolInvocationError: .toolInvocation(value)
        case let value as EvidenceError: .evidence(value)
        case let value as ToolReceiptError: .receipt(value)
        case let value as ToolResourceError: .resource(value)
        case let value as ToolSchedulerError: .scheduler(value)
        case let value as AgentJournalError: .journal(value)
        case let value as AgentMutationPersistenceError: .mutationPersistence(value)
        case let value as AgentContextError: .context(value)
        default: .unclassified
        }
    }

    private static func outcome(from result: ConversationRunResult) -> AgentLoopOutcome {
        switch result {
        case .completed: .completed
        case .refused: .refused
        case .incomplete(let reason): .incomplete(reason)
        }
    }
}
