import AgentCore
import AgentModels
import Foundation

public enum ConversationControllerError: Error, Equatable, Sendable {
    case emptyInput
    case runInProgress
}

public enum ConversationRunResult: Equatable, Sendable {
    case completed
    case refused
    case incomplete(StopReason)
}

public struct ConversationRunHandle: Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let events: AsyncStream<AgentEvent>
    private let cancelOperation: @Sendable () async -> Void
    private let waitOperation: @Sendable () async throws -> ConversationRunResult
    private let drainOperation: @Sendable () async throws -> Void

    init(
        id: UUID,
        sessionID: UUID,
        events: AsyncStream<AgentEvent>,
        cancel: @escaping @Sendable () async -> Void,
        wait: @escaping @Sendable () async throws -> ConversationRunResult,
        waitForDrain: @escaping @Sendable () async throws -> Void
    ) {
        self.id = id
        self.sessionID = sessionID
        self.events = events
        cancelOperation = cancel
        waitOperation = wait
        drainOperation = waitForDrain
    }

    public init(_ run: AgentRun) {
        self.init(
            id: run.id,
            sessionID: run.sessionID,
            events: run.events,
            cancel: { await run.cancel() },
            wait: {
                switch try await run.wait().outcome {
                case .completed: .completed
                case .refused: .refused
                case .incomplete(let reason): .incomplete(reason)
                }
            },
            waitForDrain: { try await run.waitForDrain() }
        )
    }

    public func cancel() async { await cancelOperation() }
    public func wait() async throws -> ConversationRunResult { try await waitOperation() }
    public func waitForDrain() async throws { try await drainOperation() }
}

public struct ConversationStartRequest: Sendable {
    public let text: String
    public let displayText: String?
    public let binding: AgentModelBinding?
    public let expectedRevision: UInt64?
    public let handoffWarning: String?

    public init(
        text: String,
        displayText: String? = nil,
        binding: AgentModelBinding? = nil,
        expectedRevision: UInt64? = nil,
        handoffWarning: String? = nil
    ) {
        self.text = text
        self.displayText = displayText
        self.binding = binding
        self.expectedRevision = expectedRevision
        self.handoffWarning = handoffWarning
    }
}

public protocol ConversationSessionHandle: Sendable {
    func start(_ request: ConversationStartRequest) async throws -> ConversationRunHandle
    func conversationSnapshot() async -> AgentConversationSnapshot
}

public actor AgentConversationSessionHandle: ConversationSessionHandle {
    private let session: AgentSession

    public init(session: AgentSession) {
        self.session = session
    }

    public func start(_ request: ConversationStartRequest) async throws -> ConversationRunHandle {
        if let binding = request.binding {
            return ConversationRunHandle(
                try await session.run(
                    request.text,
                    using: binding,
                    expectedConversationRevision: request.expectedRevision
                )
            )
        }
        return ConversationRunHandle(try await session.run(request.text))
    }

    public func conversationSnapshot() async -> AgentConversationSnapshot {
        await session.conversationSnapshot()
    }
}
