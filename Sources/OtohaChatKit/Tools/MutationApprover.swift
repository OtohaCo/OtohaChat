import Foundation

public struct MutationApprovalRequest: Equatable, Sendable {
    public let toolName: String
    public let summary: String
    public let payloadJSON: String

    public init(toolName: String, summary: String, payloadJSON: String) {
        self.toolName = toolName
        self.summary = summary
        self.payloadJSON = payloadJSON
    }
}

public protocol MutationApprover: Sendable {
    func decide(_ request: MutationApprovalRequest) async -> Bool
}

public struct AutoAllowMutations: MutationApprover {
    public init() {}
    public func decide(_ request: MutationApprovalRequest) async -> Bool { true }
}

public struct AutoDenyMutations: MutationApprover {
    public init() {}
    public func decide(_ request: MutationApprovalRequest) async -> Bool { false }
}

/// Bridges UI confirmation onto the Core `authorize` hook.
public actor PromptingMutationApprover: MutationApprover {
    public private(set) var pending: MutationApprovalRequest?
    private var continuation: CheckedContinuation<Bool, Never>?

    public init() {}

    public func decide(_ request: MutationApprovalRequest) async -> Bool {
        if continuation != nil {
            return false
        }
        pending = request
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    public func respond(_ allowed: Bool) {
        pending = nil
        continuation?.resume(returning: allowed)
        continuation = nil
    }
}
