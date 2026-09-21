import AgentCore
import AgentModels
import AgentUsage
import Foundation

/// Logical vs physical run states. `idle` means the previous Run has drained.
public enum ConversationPhase: String, Equatable, Sendable, Codable {
    case idle
    case starting
    case running
    case stopRequested
    case draining
}

public enum UsageDisplayState: Equatable, Sendable {
    case noSamples
    case inProgress
    case finalized
    case partial
}

public func usageDisplayState(
    _ summary: UsageSummary,
    phase: ConversationPhase,
    isCurrentResponse: Bool = true
) -> UsageDisplayState {
    guard summary.observedResponseCount > 0 else { return .noSamples }
    if summary.provisionalResponseCount > 0 {
        guard isCurrentResponse else { return .partial }
        switch phase {
        case .starting, .running, .stopRequested:
            return .inProgress
        case .draining, .idle:
            return .partial
        }
    }
    return summary.inputTokens.complete && summary.outputTokens.complete ? .finalized : .partial
}

public enum ConversationTerminal: Equatable, Sendable {
    case completed
    case refused
    case incomplete(StopReason)
    case failed(AgentFailure)
    case cancelled
}

public struct DisplayUserMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public struct DisplayAssistantTurn: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var responseID: String?
    public var text: String
    public var reasoning: String
    public var usage: ModelUsage
    public var usageSummary: UsageSummary

    public init(
        id: UUID = UUID(),
        responseID: String? = nil,
        text: String = "",
        reasoning: String = "",
        usage: ModelUsage = .init(),
        usageSummary: UsageSummary = .empty
    ) {
        self.id = id
        self.responseID = responseID
        self.text = text
        self.reasoning = reasoning
        self.usage = usage
        self.usageSummary = usageSummary
    }
}

public enum DisplayToolState: String, Equatable, Sendable, Codable {
    case proposed
    case admitted
    case completed
    case failed
}

public struct DisplayToolCall: Identifiable, Equatable, Sendable {
    public let id: ToolCallID
    public let rowID: UUID
    public var name: String
    public var argumentsJSON: String
    public var resultText: String
    public var state: DisplayToolState
    public var isError: Bool
    public var receiptValidated: Bool
    public var failureText: String?

    public init(
        id: ToolCallID,
        rowID: UUID = UUID(),
        name: String = "",
        argumentsJSON: String = "",
        resultText: String = "",
        state: DisplayToolState = .proposed,
        isError: Bool = false,
        receiptValidated: Bool = false,
        failureText: String? = nil
    ) {
        self.id = id
        self.rowID = rowID
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.resultText = resultText
        self.state = state
        self.isError = isError
        self.receiptValidated = receiptValidated
        self.failureText = failureText
    }
}

public enum ConversationItem: Identifiable, Equatable, Sendable {
    case user(DisplayUserMessage)
    case assistant(DisplayAssistantTurn)
    case tool(DisplayToolCall)

    public var id: String {
        switch self {
        case .user(let message): "user-\(message.id.uuidString)"
        case .assistant(let turn): "assistant-\(turn.id.uuidString)"
        case .tool(let call): "tool-\(call.rowID.uuidString)"
        }
    }
}

public struct ConversationSnapshot: Equatable, Sendable {
    public let conversationID: UUID
    public var generation: UInt64
    public var runID: UUID?
    public var phase: ConversationPhase
    public var terminal: ConversationTerminal?
    public var model: ModelID?
    public var items: [ConversationItem]
    public var currentAssistantTurnID: UUID?
    public var currentResponseUsage: UsageSummary
    public var latestRunUsage: UsageSummary
    public var sessionUsage: UsageSummary
    public var usageDiagnosticCount: Int
    public var pendingConfigurationNote: String?
    public var handoffWarning: String?
    public var runFailureText: String?
    public var executionReport: RunExecutionReport?

    public init(
        conversationID: UUID,
        generation: UInt64 = 0,
        runID: UUID? = nil,
        phase: ConversationPhase = .idle,
        terminal: ConversationTerminal? = nil,
        model: ModelID? = nil,
        items: [ConversationItem] = [],
        currentAssistantTurnID: UUID? = nil,
        currentResponseUsage: UsageSummary = .empty,
        latestRunUsage: UsageSummary = .empty,
        sessionUsage: UsageSummary = .empty,
        usageDiagnosticCount: Int = 0,
        pendingConfigurationNote: String? = nil,
        handoffWarning: String? = nil,
        runFailureText: String? = nil,
        executionReport: RunExecutionReport? = nil
    ) {
        self.conversationID = conversationID
        self.generation = generation
        self.runID = runID
        self.phase = phase
        self.terminal = terminal
        self.model = model
        self.items = items
        self.currentAssistantTurnID = currentAssistantTurnID
        self.currentResponseUsage = currentResponseUsage
        self.latestRunUsage = latestRunUsage
        self.sessionUsage = sessionUsage
        self.usageDiagnosticCount = usageDiagnosticCount
        self.pendingConfigurationNote = pendingConfigurationNote
        self.handoffWarning = handoffWarning
        self.runFailureText = runFailureText
        self.executionReport = executionReport
    }

    public var isBusy: Bool { phase != .idle }
}

public struct ConversationProjection: Sendable {
    public private(set) var snapshot: ConversationSnapshot
    private let maxItems: Int

    public init(conversationID: UUID, maxItems: Int = 400) {
        precondition(maxItems > 0)
        snapshot = ConversationSnapshot(conversationID: conversationID)
        self.maxItems = maxItems
    }

    public mutating func beginUserTurn(_ text: String, generation: UInt64) {
        snapshot.generation = generation
        snapshot.runID = nil
        snapshot.phase = .starting
        snapshot.terminal = nil
        snapshot.runFailureText = nil
        snapshot.executionReport = nil
        snapshot.currentAssistantTurnID = nil
        snapshot.currentResponseUsage = .empty
        snapshot.latestRunUsage = .empty
        snapshot.handoffWarning = nil
        append(.user(.init(text: text)))
        let turn = DisplayAssistantTurn()
        snapshot.currentAssistantTurnID = turn.id
        append(.assistant(turn))
    }

    public mutating func restoreItems(_ items: [ConversationItem]) {
        snapshot.items = Array(items.suffix(maxItems))
    }

    public mutating func setPhase(_ phase: ConversationPhase) {
        snapshot.phase = phase
    }

    public mutating func setPendingConfigurationNote(_ note: String?) {
        snapshot.pendingConfigurationNote = note
    }

    public mutating func setHandoffWarning(_ warning: String?) {
        snapshot.handoffWarning = warning
    }

    public mutating func updateExecutionReport(_ report: RunExecutionReport?) {
        snapshot.executionReport = report
    }

    public mutating func clearRunAfterDrain() {
        snapshot.runID = nil
        snapshot.phase = .idle
        snapshot.currentAssistantTurnID = nil
    }

    public mutating func setTerminal(_ terminal: ConversationTerminal) {
        snapshot.terminal = terminal
        if case .failed(let failure) = terminal {
            snapshot.runFailureText = RunFailureText.describe(failure)
            failOpenProposedTools(snapshot.runFailureText)
        } else {
            snapshot.runFailureText = nil
        }
    }

    public mutating func setRunFailureText(_ text: String) {
        snapshot.runFailureText = text
        failOpenProposedTools(text)
    }

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case .runStarted(let info):
            snapshot.runID = info.runID
            snapshot.model = info.model
        case .turnStarted:
            snapshot.currentResponseUsage = .empty
            if !reuseEmptyAssistantPlaceholder() {
                let turn = DisplayAssistantTurn()
                snapshot.currentAssistantTurnID = turn.id
                append(.assistant(turn))
            }
        case .model(let event):
            apply(event)
        case .toolStarted(let call):
            updateTool(call.id, name: call.name) {
                $0.argumentsJSON = call.argumentsJSON
                $0.state = .admitted
            }
        case .toolCompleted(let result):
            updateTool(result.callID) {
                $0.state = .completed
                $0.isError = result.isError
                $0.resultText = renderContent(result.content)
            }
        case .toolReceiptValidated(let receipt):
            updateTool(receipt.callID) { $0.receiptValidated = true }
        case .toolFailed(let callID, let failure):
            updateTool(callID) {
                $0.state = .failed
                $0.isError = true
                $0.failureText = RunFailureText.describe(failure)
            }
        case .steeringApplied(_, let text):
            append(.user(.init(text: text)))
        case .runFinished(let termination):
            setTerminal(Self.terminal(for: termination))
        }
    }

    private mutating func failOpenProposedTools(_ text: String?) {
        for index in snapshot.items.indices {
            guard case .tool(var call) = snapshot.items[index], call.state == .proposed else { continue }
            call.state = .failed
            call.isError = true
            if call.failureText == nil { call.failureText = text }
            snapshot.items[index] = .tool(call)
        }
    }

    private mutating func apply(_ event: ModelEvent) {
        switch event {
        case .responseStarted(let info):
            updateCurrentAssistant { $0.responseID = info.id }
        case .textDelta(let text):
            updateCurrentAssistant { $0.text += text }
        case .reasoningDelta(let text):
            updateCurrentAssistant { $0.reasoning += text }
        case .providerContinuation:
            break
        case .toolCallStarted(let callID, let name):
            updateTool(callID, name: name) { _ in }
        case .toolCallArgumentsDelta(let callID, let arguments):
            updateTool(callID) { $0.argumentsJSON += arguments }
        case .toolCallCompleted(let call):
            updateTool(call.id, name: call.name) {
                $0.argumentsJSON = call.argumentsJSON
            }
        case .usage(let usage):
            updateCurrentAssistant { $0.usage = Self.merge($0.usage, usage) }
        case .responseCompleted(let response):
            updateCurrentAssistant {
                $0.responseID = response.info.id
                $0.usage = Self.merge($0.usage, response.usage)
                if $0.text.isEmpty {
                    let text = renderContent(response.content)
                    if !text.isEmpty { $0.text = text }
                }
            }
        }
    }

    public mutating func updateUsage(
        response: UsageSummary,
        run: UsageSummary,
        session: UsageSummary,
        diagnosticCount: Int
    ) {
        snapshot.currentResponseUsage = response
        snapshot.latestRunUsage = run
        snapshot.sessionUsage = session
        snapshot.usageDiagnosticCount = diagnosticCount
        updateCurrentAssistant {
            $0.usage = response.reportedUsage
            $0.usageSummary = response
        }
    }

    private mutating func reuseEmptyAssistantPlaceholder() -> Bool {
        guard let id = snapshot.currentAssistantTurnID,
              let last = snapshot.items.last,
              case .assistant(let turn) = last,
              turn.id == id,
              turn.text.isEmpty,
              turn.reasoning.isEmpty
        else {
            return false
        }
        return true
    }

    private mutating func updateCurrentAssistant(_ update: (inout DisplayAssistantTurn) -> Void) {
        guard let index = snapshot.items.lastIndex(where: {
            if case .assistant = $0 { return true }
            return false
        }), case .assistant(var turn) = snapshot.items[index] else { return }
        update(&turn)
        snapshot.items[index] = .assistant(turn)
    }

    private mutating func updateTool(
        _ id: ToolCallID,
        name: String = "",
        _ update: (inout DisplayToolCall) -> Void
    ) {
        if let index = snapshot.items.firstIndex(where: {
            if case .tool(let call) = $0 { return call.id == id }
            return false
        }), case .tool(var call) = snapshot.items[index] {
            if !name.isEmpty { call.name = name }
            update(&call)
            snapshot.items[index] = .tool(call)
            return
        }
        var call = DisplayToolCall(id: id, name: name)
        update(&call)
        append(.tool(call))
    }

    private mutating func append(_ item: ConversationItem) {
        snapshot.items.append(item)
        if snapshot.items.count > maxItems {
            snapshot.items.removeFirst(snapshot.items.count - maxItems)
        }
    }

    private static func terminal(for termination: AgentRunTermination) -> ConversationTerminal {
        switch termination {
        case .result(let result):
            switch result.outcome {
            case .completed: .completed
            case .refused: .refused
            case .incomplete(let reason): .incomplete(reason)
            }
        case .failed(let failure): .failed(failure)
        case .cancelled: .cancelled
        }
    }

    private static func merge(_ existing: ModelUsage, _ newer: ModelUsage) -> ModelUsage {
        .init(
            inputTokens: newer.inputTokens ?? existing.inputTokens,
            outputTokens: newer.outputTokens ?? existing.outputTokens,
            cachedInputTokens: newer.cachedInputTokens ?? existing.cachedInputTokens,
            cacheWriteInputTokens: newer.cacheWriteInputTokens ?? existing.cacheWriteInputTokens,
            reasoningTokens: newer.reasoningTokens ?? existing.reasoningTokens
        )
    }
}

func renderContent(_ content: [ModelContent]) -> String {
    content.compactMap { part -> String? in
        switch part {
        case .text(let text):
            return text
        case .json(let value):
            return (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? String(describing: value)
        case .reasoning, .providerContinuation:
            return nil
        }
    }
    .joined(separator: "\n")
}

public struct ConversationSnapshotMailbox: Sendable {
    public let snapshots: AsyncStream<ConversationSnapshot>
    private let continuation: AsyncStream<ConversationSnapshot>.Continuation

    public init(initial: ConversationSnapshot, bufferingLimit: Int = 1) {
        precondition(bufferingLimit > 0)
        let channel = AsyncStream<ConversationSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(bufferingLimit)
        )
        snapshots = channel.stream
        continuation = channel.continuation
        continuation.yield(initial)
    }

    public func send(_ snapshot: ConversationSnapshot) {
        continuation.yield(snapshot)
    }

    public func finish() {
        continuation.finish()
    }
}
