import Foundation

public enum PathSandboxError: Error, Equatable, Sendable {
    case emptyPath
    case escapeAttempt(String)
    case symlinkTargetNotAuthorized(String)
    case notAFile(String)
    case notADirectory(String)
    case deniedSensitiveName(String)
    case fileTooLarge(Int)
    case ioFailed(String)
}

public struct PathSandbox: Sendable {
    public static let defaultSensitiveNames: Set<String> = [
        ".env", ".env.local", ".env.live", ".netrc",
        "id_rsa", "id_ecdsa", "id_ed25519",
        "credentials.json", "secrets.json",
    ]

    public static let defaultSensitiveExtensions: Set<String> = [
        "pem", "p12", "pfx", "key", "cer", "der", "mobileprovision",
    ]

    public let root: URL
    public let maxFileBytes: Int
    public let sensitiveNames: Set<String>
    public let sensitiveExtensions: Set<String>

    public init(
        root: URL,
        maxFileBytes: Int = 256_000,
        sensitiveNames: Set<String> = PathSandbox.defaultSensitiveNames,
        sensitiveExtensions: Set<String> = PathSandbox.defaultSensitiveExtensions
    ) {
        self.root = root.standardizedFileURL
        self.maxFileBytes = maxFileBytes
        self.sensitiveNames = sensitiveNames
        self.sensitiveExtensions = sensitiveExtensions
    }

    public func resolve(
        _ relative: String,
        followAuthorizedSymlinks: Bool = true
    ) throws -> URL {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PathSandboxError.emptyPath }
        let rootPath = root.path
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL

        guard isInsideRoot(candidate.path, rootPath: rootPath) else {
            throw PathSandboxError.escapeAttempt(trimmed)
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
        if exists {
            let values = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                let destination = candidate.resolvingSymlinksInPath().standardizedFileURL
                guard followAuthorizedSymlinks, isInsideRoot(destination.path, rootPath: rootPath) else {
                    throw PathSandboxError.symlinkTargetNotAuthorized(trimmed)
                }
                return destination
            }
        }
        return candidate
    }

    public func rejectIfSensitive(_ url: URL) throws {
        let name = url.lastPathComponent.lowercased()
        if sensitiveNames.contains(name) || name.hasPrefix(".env.") {
            throw PathSandboxError.deniedSensitiveName(url.lastPathComponent)
        }
        let ext = url.pathExtension.lowercased()
        if sensitiveExtensions.contains(ext) {
            throw PathSandboxError.deniedSensitiveName(url.lastPathComponent)
        }
    }

    public func readText(_ relative: String) throws -> (url: URL, text: String) {
        let url = try resolve(relative)
        try rejectIfSensitive(url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw PathSandboxError.ioFailed("File not found: \(relative)")
        }
        if isDirectory.boolValue {
            throw PathSandboxError.notAFile(relative)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int ?? 0
        if size > maxFileBytes {
            throw PathSandboxError.fileTooLarge(size)
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PathSandboxError.ioFailed("File is not UTF-8 text: \(relative)")
        }
        return (url, text)
    }

    public func list(_ relative: String, limit: Int = 200) throws -> [String] {
        let url = relative.isEmpty ? root : try resolve(relative)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PathSandboxError.notADirectory(relative)
        }
        var contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        if relative.isEmpty {
            let agents = root.appendingPathComponent(".agents")
            var isAgentsDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: agents.path, isDirectory: &isAgentsDirectory),
               isAgentsDirectory.boolValue
            {
                contents.append(agents)
            }
        }
        return Array(contents.prefix(limit)).map { relativePath($0) }.sorted()
    }

    public func relativePath(_ url: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let itemPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        if itemPath == rootPath { return "." }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard itemPath.hasPrefix(prefix) else {
            return url.lastPathComponent
        }
        return String(itemPath.dropFirst(prefix.count))
    }

    private func isInsideRoot(_ path: String, rootPath: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        if normalized == rootPath { return true }
        return normalized.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }
}
