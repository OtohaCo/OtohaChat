/// Adapted from SwiftAgent 1.0.0-rc.3 `Examples/ExecutionReportingSupport`.
/// This is host presentation code. It does not authorize tools, write the
/// Journal, or change AgentCore settlement.
import AgentCore
import AgentModels
import AgentTools
import Foundation

public enum RuntimeTermination: Equatable, Sendable {
    case completed(AgentLoopOutcome)
    case failed(AgentFailure)
    case cancelled
}

public enum RunWaitObservation: Equatable, Sendable {
    case notObserved
    case succeeded
    case failed(AgentFailure)
}

public enum ToolExecutionStatus: Equatable, Sendable {
    case proposed
    case admitted
    case completed(isError: Bool)
    case failed(AgentFailure)
    case unknown
}

/// A bounded observation of one tool identity. It describes what the Host
/// received from the runtime; it does not authorize or replay the tool.
public struct ToolExecutionObservation: Equatable, Sendable {
    public let callID: ToolCallID
    public private(set) var name: String
    public private(set) var argumentsJSON: String
    public private(set) var status: ToolExecutionStatus
    public private(set) var executorEntered: Bool?
    public private(set) var resultPreview: String?
    public private(set) var receipt: AgentToolReceipt?

    init(call: ToolCall, status: ToolExecutionStatus) {
        callID = call.id
        name = call.name
        argumentsJSON = call.argumentsJSON
        self.status = status
        executorEntered = nil
        resultPreview = nil
        receipt = nil
    }

    init(callID: ToolCallID, name: String = "", status: ToolExecutionStatus = .unknown) {
        self.callID = callID
        self.name = name
        argumentsJSON = ""
        self.status = status
        executorEntered = nil
        resultPreview = nil
        receipt = nil
    }

    mutating func update(call: ToolCall) {
        if !call.name.isEmpty { name = call.name }
        if !call.argumentsJSON.isEmpty { argumentsJSON = call.argumentsJSON }
    }

    mutating func admit(_ call: ToolCall) {
        update(call: call)
        status = .admitted
        // `toolStarted` is admission, not executor entry.
        executorEntered = nil
    }

    mutating func propose(_ call: ToolCall) {
        update(call: call)
        status = .proposed
    }

    mutating func complete(_ result: ToolResultMessage, preview: String?) {
        status = .completed(isError: result.isError)
        // A completion event can describe a settled replay. The public event
        // contract does not expose executor entry, so keep this unknown.
        executorEntered = nil
        resultPreview = preview
    }

    mutating func fail(_ failure: AgentFailure) {
        status = .failed(failure)
        if case .toolInvocation(.authorizationDenied) = failure {
            executorEntered = false
        }
    }

    mutating func attach(_ receipt: AgentToolReceipt) {
        self.receipt = receipt
    }
}

public enum PresentationObservation: Equatable, Sendable {
    case notObserved
    case parsed(text: String)
    case malformed(reason: String)
    case contradictory(reason: String)
}

public enum ExecutionReportDiagnostic: Equatable, Sendable {
    case mismatchedRun
    case eventBeforeRunBinding
    case eventAfterObservationEnded
    case duplicateReceipt(callID: ToolCallID)
    case conflictingReceipt(callID: ToolCallID)
    case missingReceipt(callID: ToolCallID)
    case receiptWithoutToolObservation(callID: ToolCallID)
    case streamEndedWithoutTerminal
    case terminalConflict
    case waitConflict
    case contentTruncated
}

public struct ExecutionReportCoverage: Equatable, Sendable {
    public let runStarted: Bool
    public let terminalObserved: Bool
    public let waitObserved: Bool
    public let streamEnded: Bool
    public let drainCompleted: Bool

    public var isComplete: Bool {
        runStarted && terminalObserved && waitObserved && streamEnded && drainCompleted
    }

    public var isPartial: Bool {
        !isComplete && (runStarted || terminalObserved || waitObserved || streamEnded || drainCompleted)
    }
}

/// Codable display data is intentionally inert. Restoring it cannot produce
/// Evidence, a Receipt, an authorization decision, or a journal mutation.
public struct ExecutionReportSnapshot: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let runID: UUID
    public let receipts: [AgentToolReceipt]
    public let modelText: String

    public var canAuthorizeTools: Bool { false }
    public var canCreateEvidence: Bool { false }

    public init(sessionID: UUID, runID: UUID, receipts: [AgentToolReceipt], modelText: String) {
        self.sessionID = sessionID
        self.runID = runID
        self.receipts = receipts
        self.modelText = modelText
    }
}

public struct RunExecutionReport: Equatable, Sendable {
    public let sessionID: UUID
    public let runID: UUID
    public let runtimeTermination: RuntimeTermination?
    public let waitObservation: RunWaitObservation
    public let toolObservations: [ToolExecutionObservation]
    public let receipts: [AgentToolReceipt]
    public let modelText: String
    public let finalModelText: String?
    public let presentation: PresentationObservation
    public let coverage: ExecutionReportCoverage
    public let diagnostics: [ExecutionReportDiagnostic]

    public var snapshot: ExecutionReportSnapshot {
        .init(sessionID: sessionID, runID: runID, receipts: receipts, modelText: modelText)
    }

    init(
        sessionID: UUID,
        runID: UUID,
        runtimeTermination: RuntimeTermination?,
        waitObservation: RunWaitObservation,
        toolObservations: [ToolExecutionObservation],
        receipts: [AgentToolReceipt],
        modelText: String,
        finalModelText: String?,
        presentation: PresentationObservation,
        coverage: ExecutionReportCoverage,
        diagnostics: [ExecutionReportDiagnostic]
    ) {
        self.sessionID = sessionID
        self.runID = runID
        self.runtimeTermination = runtimeTermination
        self.waitObservation = waitObservation
        self.toolObservations = toolObservations
        self.receipts = receipts
        self.modelText = modelText
        self.finalModelText = finalModelText
        self.presentation = presentation
        self.coverage = coverage
        self.diagnostics = diagnostics
    }
}

/// Deterministic, synchronous reducer for one already-bound `AgentRun.events`
/// stream. Hosts own serialization by calling it from their existing actor or
/// controller; this type starts no tasks and has no executor authority.
public struct ExecutionReportReducer: Sendable {
    public static let defaultMaximumTextLength = 16 * 1024
    public static let defaultMaximumPreviewLength = 512

    private let sessionID: UUID
    private let runID: UUID
    private let maximumTextLength: Int
    private let maximumPreviewLength: Int
    private var runStarted = false
    private var terminalObserved = false
    private var streamEnded = false
    private var drainCompleted = false
    private var waitObservation: RunWaitObservation = .notObserved
    private var runtimeTermination: RuntimeTermination?
    private var streamedText = ""
    private var finalModelText: String?
    private var presentation: PresentationObservation = .notObserved
    private var diagnostics: [ExecutionReportDiagnostic] = []
    private var toolsByID: [ToolCallID: ToolExecutionObservation] = [:]
    private var toolOrder: [ToolCallID] = []
    private var receiptsByCallID: [ToolCallID: AgentToolReceipt] = [:]
    private var receiptOrder: [ToolCallID] = []

    public init(
        sessionID: UUID,
        runID: UUID,
        maximumTextLength: Int = Self.defaultMaximumTextLength,
        maximumPreviewLength: Int = Self.defaultMaximumPreviewLength
    ) {
        precondition(maximumTextLength > 0)
        precondition(maximumPreviewLength > 0)
        self.sessionID = sessionID
        self.runID = runID
        self.maximumTextLength = maximumTextLength
        self.maximumPreviewLength = maximumPreviewLength
    }

    public var report: RunExecutionReport {
        let orderedTools = toolOrder.compactMap { toolsByID[$0] }
        let text = streamedText.isEmpty ? (finalModelText ?? "") : streamedText
        return RunExecutionReport(
            sessionID: sessionID,
            runID: runID,
            runtimeTermination: runtimeTermination,
            waitObservation: waitObservation,
            toolObservations: orderedTools,
            receipts: receiptOrder.compactMap { receiptsByCallID[$0] },
            modelText: text,
            finalModelText: finalModelText,
            presentation: presentation,
            coverage: .init(
                runStarted: runStarted,
                terminalObserved: terminalObserved,
                waitObserved: waitObservation != .notObserved,
                streamEnded: streamEnded,
                drainCompleted: drainCompleted
            ),
            diagnostics: diagnostics
        )
    }

    @discardableResult
    public mutating func consume(_ event: AgentEvent) -> Bool {
        guard !streamEnded else {
            addDiagnostic(.eventAfterObservationEnded)
            return false
        }

        if case .runStarted = event {
            switch event {
            case .runStarted(let info):
                guard info.sessionID == sessionID, info.runID == runID else {
                    addDiagnostic(.mismatchedRun)
                    return false
                }
                guard !runStarted else {
                    addDiagnostic(.terminalConflict)
                    return false
                }
                runStarted = true
            default:
                break
            }
            return true
        }

        guard runStarted else {
            // AgentEvent cases after runStarted do not carry an independent
            // source identity. Reject them until the expected header binds the
            // stream so a wrong header cannot be followed by accepted body.
            addDiagnostic(.eventBeforeRunBinding)
            return false
        }

        switch event {
        case .runStarted:
            break
        case .turnStarted:
            break
        case .model(let event):
            consume(event)
        case .toolStarted(let call):
            var observation = observation(for: call.id)
            observation.admit(call)
            toolsByID[call.id] = observation
        case .toolCompleted(let result):
            var observation = observation(for: result.callID)
            observation.complete(result, preview: preview(result.content))
            toolsByID[result.callID] = observation
        case .toolReceiptValidated(let receipt):
            merge(receipt)
        case .toolFailed(let callID, let failure):
            var observation = observation(for: callID)
            observation.fail(failure)
            toolsByID[callID] = observation
            if receiptsByCallID[callID] == nil {
                addDiagnostic(.missingReceipt(callID: callID))
            }
        case .steeringApplied:
            break
        case .runFinished(let termination):
            terminalObserved = true
            setTermination(Self.termination(for: termination), fromEvent: true)
            if case .result(let result) = termination {
                recordResult(result)
            }
        }
        return true
    }

    public mutating func recordWait(_ result: Result<AgentLoopResult, AgentFailure>) {
        switch result {
        case .success(let result):
            waitObservation = .succeeded
            setTermination(.completed(result.outcome), fromEvent: false)
            recordResult(result)
        case .failure(let failure):
            waitObservation = failure == .cancelled ? .failed(.cancelled) : .failed(failure)
            setTermination(Self.termination(for: failure), fromEvent: false)
        }
    }

    /// Convenience for Hosts whose wrapper exposes only the public outcome;
    /// the terminal event still supplies the detailed result payload.
    public mutating func recordWait(outcome: Result<AgentLoopOutcome, AgentFailure>) {
        switch outcome {
        case .success(let outcome):
            waitObservation = .succeeded
            setTermination(.completed(outcome), fromEvent: false)
        case .failure(let failure):
            waitObservation = failure == .cancelled ? .failed(.cancelled) : .failed(failure)
            setTermination(Self.termination(for: failure), fromEvent: false)
        }
    }

    /// Records only the result payload observed inside a terminal event. The
    /// event itself is still the source of terminal/stream coverage.
    public mutating func recordLogicalResult(
        response: ModelResponse,
        outcome: AgentLoopOutcome,
        receipts: [AgentToolReceipt]
    ) {
        finalModelText = boundedText(Self.text(from: response.content))
        setTermination(.completed(outcome), fromEvent: false)
        for receipt in receipts { merge(receipt) }
    }

    public mutating func recordPresentation(_ observation: PresentationObservation) {
        guard runStarted else {
            addDiagnostic(.eventBeforeRunBinding)
            return
        }
        guard !isFinal else {
            addDiagnostic(.eventAfterObservationEnded)
            return
        }
        presentation = observation
    }

    /// Call after the single `for await` consumer observes stream termination.
    public mutating func markStreamEnded() {
        guard !streamEnded else { return }
        streamEnded = true
        if !terminalObserved { addDiagnostic(.streamEndedWithoutTerminal) }
    }

    /// Call after `AgentRun.waitForDrain()` returns successfully.
    public mutating func markDrainCompleted() {
        drainCompleted = true
    }

    public static func classify(_ error: any Error) -> AgentFailure {
        switch error {
        case is CancellationError: .cancelled
        case let error as AgentFailure: error
        case let error as AgentLoopError: .loop(error)
        case let error as AgentSessionError: .session(error)
        case let error as ModelProviderError: .provider(error)
        case let error as ModelStreamError: .modelStream(error)
        case let error as ToolRegistryError: .toolRegistry(error)
        case let error as ToolInvocationError: .toolInvocation(error)
        case let error as EvidenceError: .evidence(error)
        case let error as ToolReceiptError: .receipt(error)
        case let error as ToolResourceError: .resource(error)
        case let error as ToolSchedulerError: .scheduler(error)
        case let error as AgentJournalError: .journal(error)
        case let error as AgentMutationPersistenceError: .mutationPersistence(error)
        case let error as AgentContextError: .context(error)
        default: .unclassified
        }
    }

    private var isFinal: Bool { report.coverage.isComplete }

    private mutating func consume(_ event: ModelEvent) {
        switch event {
        case .responseStarted, .reasoningDelta, .providerContinuation, .toolCallArgumentsDelta, .usage:
            break
        case .textDelta(let text):
            let appended = appendBounded(text, to: streamedText)
            streamedText = appended.value
            if appended.truncated { addDiagnostic(.contentTruncated) }
        case .toolCallStarted(let callID, let name):
            var observation = observation(for: callID)
            if !name.isEmpty { observation.update(call: .init(id: callID, name: name, argumentsJSON: "")) }
            observation.propose(.init(id: callID, name: name, argumentsJSON: ""))
            toolsByID[callID] = observation
        case .toolCallCompleted(let call):
            var observation = observation(for: call.id)
            observation.propose(call)
            toolsByID[call.id] = observation
        case .responseCompleted(let response):
            finalModelText = boundedText(Self.text(from: response.content))
        }
    }

    private mutating func recordResult(_ result: AgentLoopResult) {
        finalModelText = boundedText(Self.text(from: result.response.content))
        for receipt in result.receipts { merge(receipt) }
    }

    private mutating func setTermination(_ termination: RuntimeTermination, fromEvent: Bool) {
        guard let existing = runtimeTermination else {
            runtimeTermination = termination
            return
        }
        guard existing != termination else { return }
        if fromEvent {
            runtimeTermination = termination
        }
        addDiagnostic(fromEvent ? .terminalConflict : .waitConflict)
    }

    private mutating func merge(_ receipt: AgentToolReceipt) {
        let acceptedReceipt: AgentToolReceipt
        if let existing = receiptsByCallID[receipt.callID] {
            if existing == receipt {
                // Event and final-result observations are an expected
                // idempotent overlap, not a second execution.
            } else {
                addDiagnostic(.conflictingReceipt(callID: receipt.callID))
            }
            acceptedReceipt = existing
        } else {
            receiptsByCallID[receipt.callID] = receipt
            receiptOrder.append(receipt.callID)
            acceptedReceipt = receipt
        }
        if toolsByID[receipt.callID] == nil {
            addDiagnostic(.receiptWithoutToolObservation(callID: receipt.callID))
        }
        var observation = observation(for: receipt.callID)
        if observation.receipt == nil {
            observation.attach(acceptedReceipt)
        }
        toolsByID[receipt.callID] = observation
    }

    private mutating func observation(for callID: ToolCallID) -> ToolExecutionObservation {
        if let observation = toolsByID[callID] { return observation }
        let observation = ToolExecutionObservation(callID: callID)
        toolOrder.append(callID)
        return observation
    }

    private func appendBounded(_ value: String, to target: String) -> (value: String, truncated: Bool) {
        guard !value.isEmpty else { return (target, false) }
        let remaining = maximumTextLength - target.utf8.count
        guard remaining > 0 else {
            return (target, true)
        }
        let bytes = Array(value.utf8.prefix(remaining))
        return (
            target + String(decoding: bytes, as: UTF8.self),
            bytes.count < value.utf8.count
        )
    }

    private func boundedText(_ value: String) -> String {
        String(decoding: Array(value.utf8.prefix(maximumTextLength)), as: UTF8.self)
    }

    private func preview(_ content: [ModelContent]) -> String? {
        let value = Self.text(from: content)
        guard !value.isEmpty else { return nil }
        return String(decoding: Array(value.utf8.prefix(maximumPreviewLength)), as: UTF8.self)
    }

    private mutating func addDiagnostic(_ diagnostic: ExecutionReportDiagnostic) {
        guard diagnostics.count < 64, !diagnostics.contains(diagnostic) else { return }
        diagnostics.append(diagnostic)
    }

    private static func termination(for termination: AgentRunTermination) -> RuntimeTermination {
        switch termination {
        case .result(let result): .completed(result.outcome)
        case .failed(let failure): Self.termination(for: failure)
        case .cancelled: .cancelled
        }
    }

    private static func termination(for failure: AgentFailure) -> RuntimeTermination {
        failure == .cancelled ? .cancelled : .failed(failure)
    }

    private static func text(from content: [ModelContent]) -> String {
        content.compactMap { content in
            guard case .text(let text) = content else { return nil }
            return text
        }.joined()
    }
}
