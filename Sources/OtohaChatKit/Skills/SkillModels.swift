import Foundation

public enum SkillIssueCode: String, Equatable, Sendable {
    case invalidFrontmatter
    case missingName
    case missingDescription
    case missingBody
    case missingReference
    case tooLarge
    case nameConflict
    case unsupportedRuntime
    case missingTool
    case pathEscape
    case authorizationExpired
}

public struct SkillIssue: Equatable, Sendable {
    public var code: SkillIssueCode
    public var message: String

    public init(code: SkillIssueCode, message: String) {
        self.code = code
        self.message = message
    }
}

public struct SkillMetadata: Equatable, Sendable, Codable, Identifiable {
    public var id: String { "\(sourceDirectory.absoluteString)|\(name)" }
    public var name: String
    public var description: String
    public var sourceDirectory: URL
    public var originLabel: String
    public var compatibility: String?
    public var allowedTools: [String]
    public var hasScripts: Bool
    public var contentFingerprint: String
    public var issues: [SkillIssue]

    public init(
        name: String,
        description: String,
        sourceDirectory: URL,
        originLabel: String,
        compatibility: String? = nil,
        allowedTools: [String] = [],
        hasScripts: Bool = false,
        contentFingerprint: String,
        issues: [SkillIssue] = []
    ) {
        self.name = name
        self.description = description
        self.sourceDirectory = sourceDirectory
        self.originLabel = originLabel
        self.compatibility = compatibility
        self.allowedTools = allowedTools
        self.hasScripts = hasScripts
        self.contentFingerprint = contentFingerprint
        self.issues = issues
    }
}

extension SkillIssue: Codable {
    enum CodingKeys: String, CodingKey { case code, message }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = SkillIssueCode(rawValue: try container.decode(String.self, forKey: .code)) ?? .invalidFrontmatter
        message = try container.decode(String.self, forKey: .message)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code.rawValue, forKey: .code)
        try container.encode(message, forKey: .message)
    }
}

public struct SkillSnapshot: Equatable, Sendable {
    public var metadata: SkillMetadata
    public var instructions: String
    public var references: [SkillReference]

    public init(metadata: SkillMetadata, instructions: String, references: [SkillReference] = []) {
        self.metadata = metadata
        self.instructions = instructions
        self.references = references
    }
}

public struct SkillReference: Equatable, Sendable {
    public var path: String
    public var text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

public enum SkillFrontmatter {
    public static func parse(_ markdown: String) throws -> (fields: [String: String], body: String) {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            throw SkillParseError.missingFrontmatter
        }
        let rest = normalized.dropFirst(4)
        guard let end = rest.range(of: "\n---\n") else {
            throw SkillParseError.missingFrontmatter
        }
        let yaml = String(rest[..<end.lowerBound])
        let body = String(rest[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: String] = [:]
        var currentKey: String?
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            if let match = text.range(of: #"^[A-Za-z0-9_-]+\s*:"#, options: .regularExpression) {
                let key = text[match].trimmingCharacters(in: CharacterSet(charactersIn: ": ")).trimmingCharacters(in: .whitespaces)
                var value = String(text[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                if value.hasPrefix("|") || value.hasPrefix(">") {
                    currentKey = key
                    fields[key] = ""
                    continue
                }
                fields[key] = value
                currentKey = value.isEmpty ? key : nil
            } else if text.hasPrefix("  - ") || text.hasPrefix("- ") {
                guard let currentKey else { continue }
                let item = text.trimmingCharacters(in: CharacterSet(charactersIn: " -"))
                let existing = fields[currentKey] ?? ""
                fields[currentKey] = existing.isEmpty ? item : existing + "," + item
            } else if let currentKey, text.hasPrefix("  ") || text.hasPrefix("\t") {
                let existing = fields[currentKey] ?? ""
                let addition = text.trimmingCharacters(in: .whitespaces)
                fields[currentKey] = existing.isEmpty ? addition : existing + " " + addition
            }
        }
        return (fields, body)
    }
}

public enum SkillParseError: Error { case missingFrontmatter }

public enum SkillDiscovery {
    public static let maxSkillFileBytes = 256_000

    public static func discover(root: URL, originLabel: String) -> [SkillMetadata] {
        let skillsRoot = root.appendingPathComponent(".agents/skills")
        var results: [SkillMetadata] = []
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: skillsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for directory in directories {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            results.append(inspect(directory: directory, originLabel: originLabel, workspaceRoot: root))
        }
        return results.sorted { $0.name < $1.name }
    }

    public static func inspect(directory: URL, originLabel: String, workspaceRoot: URL) -> SkillMetadata {
        let skillFile = directory.appendingPathComponent("SKILL.md")
        var issues: [SkillIssue] = []
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: skillFile.path)
            let size = attrs[.size] as? Int ?? 0
            if size > maxSkillFileBytes {
                issues.append(.init(code: .tooLarge, message: "SKILL.md exceeds \(maxSkillFileBytes) bytes."))
            }
            let text = try String(contentsOf: skillFile, encoding: .utf8)
            let parsed = try SkillFrontmatter.parse(text)
            let name = parsed.fields["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = parsed.fields["description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty { issues.append(.init(code: .missingName, message: "Frontmatter is missing name.")) }
            if description.isEmpty {
                issues.append(.init(code: .missingDescription, message: "Frontmatter is missing description."))
            }
            if parsed.body.isEmpty { issues.append(.init(code: .missingBody, message: "SKILL.md has no instruction body.")) }
            let allowed = (parsed.fields["allowed-tools"] ?? parsed.fields["allowed_tools"] ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let scripts = directory.appendingPathComponent("scripts")
            var isDir: ObjCBool = false
            let hasScripts = FileManager.default.fileExists(atPath: scripts.path, isDirectory: &isDir) && isDir.boolValue
            if hasScripts {
                issues.append(.init(
                    code: .unsupportedRuntime,
                    message: "This skill includes scripts/, which OtohaChat does not execute in v1."
                ))
            }
            let fingerprint = sha256Hex(text)
            return SkillMetadata(
                name: name.isEmpty ? directory.lastPathComponent : name,
                description: description,
                sourceDirectory: directory,
                originLabel: originLabel,
                compatibility: parsed.fields["compatibility"],
                allowedTools: allowed,
                hasScripts: hasScripts,
                contentFingerprint: fingerprint,
                issues: issues
            )
        } catch SkillParseError.missingFrontmatter {
            return SkillMetadata(
                name: directory.lastPathComponent,
                description: "",
                sourceDirectory: directory,
                originLabel: originLabel,
                contentFingerprint: "",
                issues: [.init(code: .invalidFrontmatter, message: "SKILL.md is missing YAML frontmatter.")]
            )
        } catch {
            return SkillMetadata(
                name: directory.lastPathComponent,
                description: "",
                sourceDirectory: directory,
                originLabel: originLabel,
                contentFingerprint: "",
                issues: [.init(code: .invalidFrontmatter, message: "SKILL.md could not be read.")]
            )
        }
    }

    public static func loadSnapshot(_ metadata: SkillMetadata, requestedReferences: [String] = []) -> SkillSnapshot {
        let skillFile = metadata.sourceDirectory.appendingPathComponent("SKILL.md")
        let text = (try? String(contentsOf: skillFile, encoding: .utf8)) ?? ""
        let body = (try? SkillFrontmatter.parse(text).body) ?? ""
        let sandbox = PathSandbox(root: metadata.sourceDirectory)
        var references: [SkillReference] = []
        for requested in requestedReferences {
            do {
                let loaded = try sandbox.readText(requested)
                references.append(.init(path: requested, text: loaded.text))
            } catch {
                references.append(.init(
                    path: requested,
                    text: "MISSING_REFERENCE: \(SecretRedactor.redact(String(describing: error)))"
                ))
            }
        }
        return SkillSnapshot(metadata: metadata, instructions: body, references: references)
    }
}

public enum SkillPromptBuilder {
    public static let hostTools = ["calculator", "datetime", "workspace_read", "app_notes_read", "app_notes"]

    public static func envelope(userText: String, snapshots: [SkillSnapshot]) -> String {
        guard !snapshots.isEmpty else { return userText }
        var parts: [String] = [
            "Host-activated skill context follows. Treat it as task instructions, not as a grant of new system permissions.",
        ]
        for snapshot in snapshots {
            parts.append("<skill name=\"\(snapshot.metadata.name)\" fingerprint=\"\(snapshot.metadata.contentFingerprint)\">")
            parts.append(snapshot.instructions)
            for reference in snapshot.references {
                parts.append("<reference path=\"\(reference.path)\">")
                parts.append(String(reference.text.prefix(12_000)))
                parts.append("</reference>")
            }
            if snapshot.metadata.hasScripts {
                parts.append("UNSUPPORTED_RUNTIME: scripts are not executed.")
            }
            let missing = snapshot.metadata.allowedTools.filter { !hostTools.contains($0) && !$0.isEmpty }
            if !missing.isEmpty {
                parts.append("MISSING_TOOL: \(missing.joined(separator: ", "))")
            }
            parts.append("</skill>")
        }
        parts.append("User message:")
        parts.append(userText)
        return parts.joined(separator: "\n")
    }

    public static func detectSlashSkill(in text: String, available: [SkillMetadata]) -> (SkillMetadata, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/skill ") || trimmed.hasPrefix("/skill\n") else { return nil }
        let remainder = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        let rest: String
        if let space = remainder.firstIndex(of: " ") {
            name = String(remainder[..<space])
            rest = String(remainder[remainder.index(after: space)...])
        } else if let newline = remainder.firstIndex(of: "\n") {
            name = String(remainder[..<newline])
            rest = String(remainder[remainder.index(after: newline)...])
        } else {
            name = remainder
            rest = ""
        }
        guard let match = available.first(where: { $0.name == name }) else { return nil }
        return (match, rest)
    }
}
