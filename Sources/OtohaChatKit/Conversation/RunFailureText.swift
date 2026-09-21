import AgentCore
import AgentModels
import AgentTools
import Foundation

/// Host-facing text for a failed Run. Match typed failures; never echo payloads
/// that might contain credentials.
public enum RunFailureText {
    public static func describe(_ error: any Error) -> String {
        SecretRedactor.redact(raw(error))
    }

    private static func raw(_ error: any Error) -> String {
        switch error {
        case let error as AgentFailure:
            return describe(error)
        case let error as ModelProviderError:
            return provider(error)
        case let error as ModelStreamError:
            return stream(error)
        case let error as ToolRegistryError:
            return registry(error)
        case let error as ToolInvocationError:
            return invocation(error)
        case let error as AgentLoopError:
            return loop(error)
        case let error as AgentSessionError:
            return session(error)
        case let error as AgentModelBindingError:
            return binding(error)
        case is AgentJournalError:
            return "The session journal could not record this run."
        case is CancellationError:
            return "Run cancelled"
        default:
            return "The run failed; provisional output was not committed"
        }
    }

    public static func describe(_ failure: AgentFailure) -> String {
        switch failure {
        case .loop(let error): loop(error)
        case .session(let error): session(error)
        case .provider(let error): provider(error)
        case .modelStream(let error): stream(error)
        case .toolRegistry(let error): registry(error)
        case .toolInvocation(let error): invocation(error)
        case .evidence: "Required evidence was missing for a tool call."
        case .receipt: "A tool receipt could not be validated."
        case .resource: "A tool could not use a declared resource."
        case .scheduler: "The tool scheduler rejected this call."
        case .journal: "The session journal could not record this run."
        case .mutationPersistence: "A mutating tool could not be settled."
        case .context: "The conversation context could not be prepared."
        case .cancelled: "Run cancelled"
        case .unclassified: "The run failed; provisional output was not committed"
        }
    }

    private static func provider(_ error: ModelProviderError) -> String {
        guard error.message.hasPrefix("Apple model generation failed") else {
            return error.message
        }
        switch error.kind {
        case .invalidRequest:
            return "The Apple model rejected this request. A previous turn may have ended without a reply; send again or start a new chat."
        case .unavailable:
            return "The Apple model is unavailable right now."
        case .rateLimited:
            return "The Apple model is rate limited. Wait and try again."
        case .transport:
            return "The Apple model could not be reached."
        case .unsupportedCapability:
            return "This request uses a capability the Apple model does not support."
        case .invalidResponse:
            return "The Apple model returned a reply this app could not use."
        default:
            return error.message
        }
    }

    private static func registry(_ error: ToolRegistryError) -> String {
        switch error {
        case .unknownTool(let name):
            "The model called \(name), which this app does not provide."
        case .duplicateName(let name):
            "Duplicate tool registration: \(name)."
        case .truncatedCall:
            "The tool call was truncated before it could run."
        case .callIdentityMismatch:
            "The tool call identity did not match the runtime."
        case .invalidJSON:
            "The model produced tool arguments that are not valid JSON."
        case .invalidSchema(let tool, _):
            "The \(tool) tool schema is invalid."
        case .invalidArguments:
            "The model called a tool with arguments this app cannot accept."
        case .invalidOutput:
            "A tool returned output that did not match its schema."
        }
    }

    private static func invocation(_ error: ToolInvocationError) -> String {
        switch error {
        case .invalidDefinition: "A tool definition is invalid."
        case .invalidArguments: "The model called a tool with arguments this app cannot accept."
        case .invalidOutput: "A tool returned output that did not match its schema."
        case .missingIdempotencyKey: "A tool call was missing its idempotency key."
        case .deadlineExceeded: "A tool call ran out of time."
        case .authorizationDenied: "A tool call was not authorized."
        case .mutationIntegrityUnavailable: "A mutating tool could not prove its integrity."
        case .receiptValidationUnavailable: "A tool receipt could not be checked."
        case .evidenceUnavailable: "Required evidence was missing for a tool call."
        }
    }

    private static func loop(_ error: AgentLoopError) -> String {
        switch error {
        case .modelMismatch: "The provider returned a different model than the one selected."
        case .providerMismatch: "The selected model does not match its provider."
        case .unsupportedCapabilities: "This model path does not support the required capabilities."
        case .invalidBudget: "The run budget is invalid."
        case .modelTurnLimitReached: "The run reached the model-turn limit."
        case .toolCallLimitReached: "The run reached the tool-call limit."
        case .deadlineExceeded: "The run ran out of time."
        case .reusedToolCallID: "The model reused a tool-call identity."
        case .toolTimedOut: "A tool call ran out of time."
        }
    }

    private static func session(_ error: AgentSessionError) -> String {
        switch error {
        case .emptyInput: "Enter a message before sending."
        case .runInProgress: "Wait for the current reply to finish before sending again."
        case .durableJournalRequired: "This session needs a durable journal before mutating tools can run."
        }
    }

    private static func binding(_ error: AgentModelBindingError) -> String {
        switch error {
        case .incompatibleContinuation:
            "This run cannot reuse the previous model's private continuation state."
        case .invalidProjection:
            "The conversation could not be projected for this model."
        case .staleConversationRevision:
            "The conversation changed before this run could start."
        case .providerMismatch:
            "The selected model does not match its provider."
        case .invalidIdentity:
            "The model binding identity is invalid."
        case .contextWindowUnknown, .invalidTokenBudget, .invalidTokenEstimate:
            "The model context budget could not be checked."
        case .contextBudgetExceeded:
            "This message is too large for the selected model's context window."
        }
    }

    private static func stream(_ error: ModelStreamError) -> String {
        switch error {
        case .invalidToolArguments:
            "The model produced tool arguments that are not valid JSON."
        case .invalidToolIdentity, .duplicateToolCall, .unknownToolCall, .toolCallMismatch, .invalidToolStop:
            "The model produced an incomplete or mismatched tool call."
        case .invalidContinuation, .responseMismatch, .invalidUsage, .missingTerminal, .missingStart,
             .duplicateStart, .eventAfterTerminal, .toolAlreadyCompleted:
            "The provider stream ended in an invalid state."
        }
    }
}
