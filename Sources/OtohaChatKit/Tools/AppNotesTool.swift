import AgentModels
import AgentTools
import CryptoKit
import Foundation

public struct NoteRecord: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var title: String
    public var body: String
    public var revision: String
    public var updatedAt: Date

    public init(id: String, title: String, body: String, revision: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public protocol NotesStoring: Sendable {
    func list() throws -> [NoteRecord]
    func read(id: String) throws -> NoteRecord
    func search(query: String) throws -> [NoteRecord]
    func upsert(id: String?, title: String, body: String, expectedRevision: String?) throws -> NoteRecord
}

public struct FileNotesStore: NotesStoring {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func list() throws -> [NoteRecord] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(NoteRecord.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func read(id: String) throws -> NoteRecord {
        let url = directory.appendingPathComponent("\(id).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NoteRecord.self, from: data)
    }

    public func search(query: String) throws -> [NoteRecord] {
        let needle = query.lowercased()
        return try list().filter {
            $0.title.lowercased().contains(needle) || $0.body.lowercased().contains(needle)
        }
    }

    public func upsert(id: String?, title: String, body: String, expectedRevision: String?) throws -> NoteRecord {
        let noteID = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? UUID().uuidString.lowercased()
        let url = directory.appendingPathComponent("\(noteID).json")
        if FileManager.default.fileExists(atPath: url.path) {
            let current = try read(id: noteID)
            if let expectedRevision, current.revision != expectedRevision {
                throw NotesStoreError.revisionConflict(current.revision)
            }
        } else if let expectedRevision, !expectedRevision.isEmpty {
            throw NotesStoreError.missingNote(noteID)
        }
        let revision = sha256Hex("\(title)\n\(body)\n\(Date().timeIntervalSince1970)")
        let record = NoteRecord(id: noteID, title: title, body: body, revision: revision, updatedAt: Date())
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: .atomic)
        return record
    }
}

public enum NotesStoreError: Error, Equatable, Sendable {
    case revisionConflict(String)
    case missingNote(String)
}

public struct AppNotesTool: AgentTool {
    public struct Input: Codable, Sendable {
        public var operation: String
        public var id: String?
        public var query: String?
        public var title: String?
        public var body: String?
        public var expectedRevision: String?

        public init(
            operation: String,
            id: String? = nil,
            query: String? = nil,
            title: String? = nil,
            body: String? = nil,
            expectedRevision: String? = nil
        ) {
            self.operation = operation
            self.id = id
            self.query = query
            self.title = title
            self.body = body
            self.expectedRevision = expectedRevision
        }
    }

    public struct Output: Codable, Sendable {
        public var operation: String
        public var notes: [NoteRecord]
        public var message: String

        public init(operation: String, notes: [NoteRecord], message: String) {
            self.operation = operation
            self.notes = notes
            self.message = message
        }
    }

    public static let name = "app_notes"
    public static let description = "Search and read notes in OtohaChat's private notebook. Creating or updating a note requires host confirmation and a matching revision for updates."
    public static let inputSchema = ToolSchema.object(
        properties: [
            "operation": .string,
            "id": .string,
            "query": .string,
            "title": .string,
            "body": .string,
            "expectedRevision": .string,
        ],
        required: ["operation"],
        additionalProperties: true
    )
    public static let outputSchema = ToolSchema.object(
        properties: [
            "operation": .string,
            "message": .string,
        ],
        required: ["operation", "message"]
    )

    public let policy: ToolPolicy
    private let store: any NotesStoring
    private let approver: any MutationApprover

    public init(store: any NotesStoring, approver: any MutationApprover) throws {
        self.store = store
        self.approver = approver
        switch store {
        default:
            break
        }
        policy = try ToolPolicy(
            effect: .mutation,
            execution: .exclusive,
            idempotency: .requiresReceipt,
            timeout: .seconds(20),
            authorization: .required,
            evidence: .none
        )
    }

    public static func readOnly(store: any NotesStoring) throws -> AppNotesReadTool {
        try AppNotesReadTool(store: store)
    }

    public func resourceRequirements(for input: Input) throws -> [ToolResource] {
        [.named(EvidenceReference(namespace: "app-notes", id: "notebook"))]
    }

    public func receiptExpectation(for input: Input) throws -> ToolReceiptExpectation? {
        try ToolReceiptExpectation(
            targets: [EvidenceReference(namespace: "app-notes", id: "notebook")],
            revision: .present
        )
    }

    public func authorize(_ input: Input, context: ToolContext) async throws -> ToolAuthorization {
        guard input.operation == "write" else { return .denied }
        let allowed = await approver.decide(
            .init(
                toolName: Self.name,
                summary: "Write note “\(input.title ?? "untitled")”",
                payloadJSON: context.argumentsJSON ?? ""
            )
        )
        return allowed ? .allowed : .denied
    }

    public func execute(_ input: Input, context: ToolContext) async throws -> ToolResult<Output> {
        try Task.checkCancellation()
        let record = try store.upsert(
            id: input.id,
            title: input.title ?? "Untitled",
            body: input.body ?? "",
            expectedRevision: input.expectedRevision
        )
        let target = EvidenceReference(namespace: "app-notes", id: "notebook")
        let receipt = ToolReceipt(
            operationID: context.idempotencyKey ?? context.callID.rawValue,
            status: .succeeded,
            confirmedTargets: [target],
            revision: record.revision
        )
        return ToolResult(
            output: .init(operation: "write", notes: [record], message: "Saved note \(record.id) at revision \(record.revision)."),
            evidence: [
                Evidence(
                    namespace: target.namespace,
                    id: target.id,
                    issuedAt: Date(),
                    metadata: ["revision": .string(record.revision)]
                ),
            ],
            receipt: receipt
        )
    }
}

/// Read/search stay read-only so listing notes does not require mutation admission.
public struct AppNotesReadTool: AgentTool {
    public typealias Input = AppNotesTool.Input
    public typealias Output = AppNotesTool.Output

    public static let name = "app_notes_read"
    public static let description = "Search or read notes in OtohaChat's private notebook. This tool never writes."
    public static let inputSchema = AppNotesTool.inputSchema
    public static let outputSchema = AppNotesTool.outputSchema
    public let policy: ToolPolicy
    private let store: any NotesStoring

    public init(store: any NotesStoring) throws {
        self.store = store
        policy = try .readOnly(
            authorization: .notRequired,
            recoverableErrors: .modelVisible
        )
    }

    public func authorize(_ input: Input, context: ToolContext) async throws -> ToolAuthorization {
        .allowed
    }

    public func execute(_ input: Input, context: ToolContext) async throws -> ToolResult<Output> {
        try Task.checkCancellation()
        switch input.operation {
        case "list":
            let notes = try store.list()
            return ToolResult(output: .init(operation: "list", notes: notes, message: "\(notes.count) note(s)."))
        case "read":
            guard let id = input.id else {
                throw try RecoverableToolError(code: "missing_id", message: "id is required for read.")
            }
            let note = try store.read(id: id)
            return ToolResult(output: .init(operation: "read", notes: [note], message: note.body))
        case "search":
            guard let query = input.query else {
                throw try RecoverableToolError(code: "missing_query", message: "query is required for search.")
            }
            let notes = try store.search(query: query)
            return ToolResult(output: .init(operation: "search", notes: notes, message: "\(notes.count) match(es)."))
        default:
            throw try RecoverableToolError(
                code: "unsupported_operation",
                message: "Use list, read, or search. Writing requires app_notes after user confirmation."
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

func sha256Hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
