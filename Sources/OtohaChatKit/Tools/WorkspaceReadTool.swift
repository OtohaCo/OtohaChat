import AgentModels
import AgentTools
import Foundation

public struct WorkspaceReadTool: AgentTool {
    public struct Input: Codable, Sendable {
        public var operation: String
        public var path: String?
        public var query: String?

        public init(operation: String, path: String? = nil, query: String? = nil) {
            self.operation = operation
            self.path = path
            self.query = query
        }
    }

    public struct Output: Codable, Sendable {
        public var operation: String
        public var path: String?
        public var content: String
        public var matches: [String]

        public init(operation: String, path: String? = nil, content: String, matches: [String] = []) {
            self.operation = operation
            self.path = path
            self.content = content
            self.matches = matches
        }
    }

    public static let name = "workspace_read"
    public static let description = """
    List, search, or read UTF-8 text inside the user-authorized workspace. Returns relative paths for citation.
    Installed skills live in .agents/skills. To see them, list that folder. Do not search the whole workspace for the word skills.
    Search matches path names first, then UTF-8 text, stays under optional path, and skips .git, node_modules, and build trees.
    """
    public static let inputSchema = ToolSchema.object(
        properties: [
            "operation": .string,
            "path": .string,
            "query": .string,
        ],
        required: ["operation"],
        additionalProperties: true
    )
    public static let outputSchema = ToolSchema.object(
        properties: [
            "operation": .string,
            "path": .string,
            "content": .string,
            "matches": .array(items: .string),
        ],
        required: ["operation", "content"]
    )

    public let policy: ToolPolicy
    private let rootProvider: @Sendable () -> URL?

    public init(rootProvider: @escaping @Sendable () -> URL?) throws {
        self.rootProvider = rootProvider
        policy = try .readOnly(
            timeout: .seconds(20),
            authorization: .notRequired,
            recoverableErrors: .modelVisible
        )
    }

    public func authorize(_ input: Input, context: ToolContext) async throws -> ToolAuthorization {
        .allowed
    }

    public func execute(_ input: Input, context: ToolContext) async throws -> ToolResult<Output> {
        try Task.checkCancellation()
        guard let root = rootProvider() else {
            throw try RecoverableToolError(
                code: "workspace_not_authorized",
                message: "The user has not authorized a workspace folder."
            )
        }
        let sandbox = PathSandbox(root: root)
        switch input.operation {
        case "list":
            let entries = try sandbox.list(input.path ?? "")
            return ToolResult(output: .init(
                operation: "list",
                path: input.path,
                content: entries.joined(separator: "\n"),
                matches: entries
            ))
        case "read":
            guard let path = input.path else {
                throw try RecoverableToolError(code: "missing_path", message: "path is required for read.")
            }
            let result = try sandbox.readText(path)
            let relative = sandbox.relativePath(result.url)
            return ToolResult(output: .init(
                operation: "read",
                path: relative,
                content: bounded(result.text),
                matches: [relative]
            ))
        case "search":
            guard let query = input.query, !query.isEmpty else {
                throw try RecoverableToolError(code: "missing_query", message: "query is required for search.")
            }
            let result = try search(sandbox: sandbox, query: query, relativePath: input.path)
            var content = result.matches.joined(separator: "\n")
            if content.isEmpty {
                content = "No matches under \(result.scope)."
            }
            if result.truncated {
                content += "\n[truncated after scanning \(result.visited) entries; pass path to search a subdirectory]"
            }
            return ToolResult(output: .init(
                operation: "search",
                path: input.path,
                content: content,
                matches: result.matches
            ))
        default:
            throw try RecoverableToolError(
                code: "unsupported_operation",
                message: "operation must be list, read, or search."
            )
        }
    }

    private func search(sandbox: PathSandbox, query: String, relativePath: String?) throws -> WorkspaceFileSearch.Result {
        try WorkspaceFileSearch.run(sandbox: sandbox, query: query, scopedPath: relativePath)
    }

    private func bounded(_ text: String) -> String {
        if text.count <= 8_000 { return text }
        return String(text.prefix(8_000)) + "\n[truncated]"
    }
}

/// Bounded workspace walk. Skills live in `.agents`, which FileManager treats as hidden,
/// so a naive skip-hidden search never finds them and then times out reading the rest of the tree.
enum WorkspaceFileSearch: Sendable {
    struct Result: Equatable, Sendable {
        var matches: [String]
        var visited: Int
        var truncated: Bool
        var scope: String
    }

    static let maxMatches = 40
    static let maxVisitedEntries = 2_000
    static let maxContentReads = 200
    static let maxContentBytes = 64_000

    static let skippedDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg",
        ".build", ".swiftpm", ".gradle", ".cache", ".next", ".nuxt", ".turbo",
        "DerivedData", "node_modules", "Pods", "Carthage", "vendor",
        "dist", "build", "xcuserdata",
    ]

    static let skippedContentExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "icns", "pdf",
        "zip", "gz", "xz", "bz2", "7z",
        "wasm", "o", "a", "dylib", "so", "class", "jar",
        "mp3", "mp4", "mov", "heic", "ttf", "otf", "woff", "woff2",
    ]

    static func run(sandbox: PathSandbox, query: String, scopedPath: String?) throws -> Result {
        let start: URL
        let scope: String
        if let scopedPath, !scopedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            start = try sandbox.resolve(scopedPath)
            scope = scopedPath
        } else {
            start = sandbox.root
            scope = "."
        }

        let enumerator = FileManager.default.enumerator(
            at: start,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        )
        var matches: [String] = []
        var visited = 0
        var contentReads = 0
        var truncated = false
        let needle = query.lowercased()

        while let url = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            visited += 1
            if visited > maxVisitedEntries {
                truncated = true
                break
            }

            let relative = sandbox.relativePath(url)
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
            ])

            if values.isDirectory == true {
                if shouldSkipDirectory(url.lastPathComponent, relative: relative) {
                    enumerator?.skipDescendants()
                }
                continue
            }
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            if shouldSkipHiddenFile(url.lastPathComponent, relative: relative) { continue }

            do {
                try sandbox.rejectIfSensitive(url)
                _ = try sandbox.resolve(relative)
            } catch PathSandboxError.escapeAttempt,
                    PathSandboxError.symlinkTargetNotAuthorized,
                    PathSandboxError.deniedSensitiveName {
                continue
            }

            if url.lastPathComponent.lowercased().contains(needle)
                || relative.lowercased().contains(needle)
            {
                matches.append(relative)
                if matches.count >= maxMatches { break }
                continue
            }

            let ext = url.pathExtension.lowercased()
            if skippedContentExtensions.contains(ext) { continue }
            let size = values.fileSize ?? 0
            if size <= 0 || size > maxContentBytes { continue }
            if contentReads >= maxContentReads {
                truncated = true
                continue
            }
            contentReads += 1
            if let text = try? sandbox.readText(relative).text.lowercased(),
               text.contains(needle)
            {
                matches.append(relative)
                if matches.count >= maxMatches { break }
            }
        }

        return Result(matches: matches, visited: visited, truncated: truncated, scope: scope)
    }

    static func shouldSkipDirectory(_ name: String, relative: String) -> Bool {
        if skippedDirectoryNames.contains(name) { return true }
        if name == ".agents" || relative == ".agents" || relative.hasPrefix(".agents/") {
            return false
        }
        return name.hasPrefix(".")
    }

    static func shouldSkipHiddenFile(_ name: String, relative: String) -> Bool {
        guard name.hasPrefix(".") else { return false }
        return !(relative == ".agents" || relative.hasPrefix(".agents/"))
    }
}
