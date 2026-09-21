import Foundation

public struct AppFileLocations: Sendable {
    public let root: URL
    public let sessions: URL
    public let notes: URL
    public let settings: URL

    public init(root: URL) {
        self.root = root
        sessions = root.appendingPathComponent("Sessions", isDirectory: true)
        notes = root.appendingPathComponent("Notes", isDirectory: true)
        settings = root.appendingPathComponent("settings.json")
    }

    public static func `default`(fileManager: FileManager = .default) throws -> AppFileLocations {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let root = base.appendingPathComponent("OtohaChat", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var locations = AppFileLocations(root: root)
        try fileManager.createDirectory(at: locations.sessions, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: locations.notes, withIntermediateDirectories: true)
        return locations
    }

    public func sessionDirectory(id: UUID) -> URL {
        sessions.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    public func journalURL(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("journal.log")
    }

    public func transcriptURL(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("transcript.json")
    }
}

public struct ChatTranscript: Equatable, Sendable, Codable {
    public var conversationID: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var profileID: UUID
    public var modelName: String
    public var reasoning: ReasoningConfiguration
    public var items: [PersistedTranscriptItem]
    public var enabledSkillNames: [String]
    public var workspacePath: String?

    public init(
        conversationID: UUID,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        profileID: UUID,
        modelName: String,
        reasoning: ReasoningConfiguration,
        items: [PersistedTranscriptItem] = [],
        enabledSkillNames: [String] = [],
        workspacePath: String? = nil
    ) {
        self.conversationID = conversationID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.profileID = profileID
        self.modelName = modelName
        self.reasoning = reasoning
        self.items = items
        self.enabledSkillNames = enabledSkillNames
        self.workspacePath = workspacePath
    }
}

public enum PersistedTranscriptItem: Equatable, Sendable, Codable {
    case user(id: UUID, text: String)
    case assistant(id: UUID, text: String, reasoning: String)
    case tool(id: String, rowID: UUID, name: String, arguments: String, result: String, isError: Bool)

    public init(_ item: ConversationItem) {
        switch item {
        case .user(let message):
            self = .user(id: message.id, text: message.text)
        case .assistant(let turn):
            self = .assistant(id: turn.id, text: turn.text, reasoning: turn.reasoning)
        case .tool(let call):
            self = .tool(
                id: call.id.rawValue,
                rowID: call.rowID,
                name: call.name,
                arguments: call.argumentsJSON,
                result: call.resultText,
                isError: call.isError
            )
        }
    }

    public var conversationItem: ConversationItem {
        switch self {
        case .user(let id, let text):
            return .user(.init(id: id, text: text))
        case .assistant(let id, let text, let reasoning):
            return .assistant(.init(id: id, text: text, reasoning: reasoning))
        case .tool(let id, let rowID, let name, let arguments, let result, let isError):
            return .tool(.init(
                id: .init(rawValue: id),
                rowID: rowID,
                name: name,
                argumentsJSON: arguments,
                resultText: result,
                state: isError ? .failed : .completed,
                isError: isError
            ))
        }
    }
}

public struct TranscriptStore: Sendable {
    public let locations: AppFileLocations

    public init(locations: AppFileLocations) {
        self.locations = locations
    }

    public func save(_ transcript: ChatTranscript) throws {
        let directory = locations.sessionDirectory(id: transcript.conversationID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var copy = transcript
        copy.updatedAt = Date()
        let data = try JSONEncoder().encode(copy)
        try data.write(to: locations.transcriptURL(id: transcript.conversationID), options: .atomic)
    }

    public func load(id: UUID) throws -> ChatTranscript {
        let data = try Data(contentsOf: locations.transcriptURL(id: id))
        return try JSONDecoder().decode(ChatTranscript.self, from: data)
    }

    public func list() throws -> [ChatTranscript] {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: locations.sessions,
            includingPropertiesForKeys: nil
        )) ?? []
        return directories.compactMap { directory in
            let url = directory.appendingPathComponent("transcript.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(ChatTranscript.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func delete(id: UUID) throws {
        let directory = locations.sessionDirectory(id: id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

public struct SettingsStore: Sendable {
    public let locations: AppFileLocations

    public init(locations: AppFileLocations) {
        self.locations = locations
    }

    public func load() throws -> ProviderSettingsDocument {
        guard FileManager.default.fileExists(atPath: locations.settings.path) else {
            return ProviderSettingsDocument()
        }
        let data = try Data(contentsOf: locations.settings)
        return try JSONDecoder().decode(ProviderSettingsDocument.self, from: data)
    }

    public func save(_ document: ProviderSettingsDocument) throws {
        let data = try JSONEncoder().encode(document)
        try data.write(to: locations.settings, options: .atomic)
    }
}
