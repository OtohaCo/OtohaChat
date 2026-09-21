import Foundation

public final class WorkspaceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var root: URL?

    public init(root: URL? = nil) {
        self.root = root
    }

    public func current() -> URL? {
        lock.withLock { root }
    }

    public func set(_ url: URL?) {
        lock.withLock { root = url }
    }
}

public final class EnabledSkillGate: @unchecked Sendable {
    private let lock = NSLock()
    private var names: Set<String> = []

    public init() {}

    public func current() -> Set<String> {
        lock.withLock { names }
    }

    public func set(_ names: Set<String>) {
        lock.withLock { self.names = names }
    }
}
