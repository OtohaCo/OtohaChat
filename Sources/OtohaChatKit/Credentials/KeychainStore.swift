import Foundation
import Security

public protocol SecretStore: Sendable {
    func save(account: String, secret: String) throws
    func load(account: String) throws -> String?
    func delete(account: String) throws
}

public enum SecretStoreError: Error, Equatable, Sendable {
    case emptyAccount
    case emptySecret
    case unexpectedStatus(OSStatus)
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func save(account: String, secret: String) throws {
        try Self.validate(account: account, secret: secret)
        lock.withLock { values[account] = secret }
    }

    public func load(account: String) throws -> String? {
        try Self.validate(account: account)
        return lock.withLock { values[account] }
    }

    public func delete(account: String) throws {
        try Self.validate(account: account)
        lock.withLock { _ = values.removeValue(forKey: account) }
    }

    private static func validate(account: String, secret: String? = "x") throws {
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecretStoreError.emptyAccount
        }
        if let secret, secret.isEmpty { throw SecretStoreError.emptySecret }
    }
}

/// Generic-password Keychain store. Secrets never appear in CustomStringConvertible.
public struct KeychainSecretStore: SecretStore, CustomStringConvertible, CustomDebugStringConvertible {
    public let service: String
    public var description: String { "KeychainSecretStore(service: \(service))" }
    public var debugDescription: String { description }

    public init(service: String = "co.otoha.OtohaChat") {
        self.service = service
    }

    public func save(account: String, secret: String) throws {
        try validate(account: account)
        guard !secret.isEmpty else { throw SecretStoreError.emptySecret }
        try delete(account: account)
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.unexpectedStatus(status) }
    }

    public func load(account: String) throws -> String? {
        try validate(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecretStoreError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        try validate(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    private func validate(account: String) throws {
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecretStoreError.emptyAccount
        }
    }
}

public enum CredentialAccount {
    public static func apiKey(profileID: UUID) -> String {
        "provider.\(profileID.uuidString.lowercased()).api-key"
    }
}
