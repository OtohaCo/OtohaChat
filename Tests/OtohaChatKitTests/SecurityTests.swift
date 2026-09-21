import OtohaChatKit
import Foundation
import Testing

struct SecretStoreTests {
    @Test func memoryStoreReplacesAndDeletesWithoutLoggingSecret() throws {
        let store = MemorySecretStore()
        try store.save(account: "provider.aaaa.api-key", secret: "sk-test-secret-value")
        #expect(try store.load(account: "provider.aaaa.api-key") == "sk-test-secret-value")
        try store.save(account: "provider.aaaa.api-key", secret: "sk-rotated")
        #expect(try store.load(account: "provider.aaaa.api-key") == "sk-rotated")
        try store.delete(account: "provider.aaaa.api-key")
        #expect(try store.load(account: "provider.aaaa.api-key") == nil)

        let description = String(describing: store)
        #expect(!description.contains("sk-rotated"))
        #expect(!description.contains("sk-test-secret-value"))
    }

    @Test func credentialAccountsAreIsolatedByProfile() throws {
        let store = MemorySecretStore()
        let first = UUID()
        let second = UUID()
        try store.save(account: CredentialAccount.apiKey(profileID: first), secret: "one")
        try store.save(account: CredentialAccount.apiKey(profileID: second), secret: "two")
        try store.delete(account: CredentialAccount.apiKey(profileID: first))
        #expect(try store.load(account: CredentialAccount.apiKey(profileID: first)) == nil)
        #expect(try store.load(account: CredentialAccount.apiKey(profileID: second)) == "two")
    }

    @Test func redactorRemovesKeyShapedValues() {
        let text = "Authorization: Bearer sk-ant-1234567890abcdef and api_key=secret"
        let redacted = SecretRedactor.redact(text)
        #expect(!redacted.contains("sk-ant-1234567890abcdef"))
        #expect(!redacted.contains("secret"))
        #expect(redacted.contains("[redacted]"))
    }
}

struct EndpointPolicyTests {
    @Test func rejectsUserinfoAndSecretQuery() {
        #expect(throws: EndpointPolicyError.userinfoForbidden) {
            try EndpointPolicy.parse("https://user:pass@api.example.com/v1", allowsInsecurePrivateNetworkHTTP: false)
        }
        #expect(throws: EndpointPolicyError.secretInQuery("api_key")) {
            try EndpointPolicy.parse("https://api.example.com/v1?api_key=abc", allowsInsecurePrivateNetworkHTTP: false)
        }
    }

    @Test func httpsRemoteAndLoopbackHTTP() throws {
        _ = try EndpointPolicy.parse("https://api.openai.com/v1/responses", allowsInsecurePrivateNetworkHTTP: false)
        _ = try EndpointPolicy.parse("http://127.0.0.1:11434/v1", allowsInsecurePrivateNetworkHTTP: false)
        #expect(throws: EndpointPolicyError.httpsRequired) {
            try EndpointPolicy.parse("http://example.com/v1", allowsInsecurePrivateNetworkHTTP: false)
        }
        #expect(throws: EndpointPolicyError.insecurePrivateNetworkDisabled) {
            try EndpointPolicy.parse("http://192.168.1.10:8080/v1", allowsInsecurePrivateNetworkHTTP: false)
        }
        _ = try EndpointPolicy.parse("http://192.168.1.10:8080/v1", allowsInsecurePrivateNetworkHTTP: true)
    }
}

struct PathSandboxTests {
    @Test func blocksEscapeAndUnauthorizedSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        let sandbox = PathSandbox(root: root)
        #expect(throws: PathSandboxError.escapeAttempt("../outside")) {
            _ = try sandbox.resolve("../outside")
        }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(throws: PathSandboxError.symlinkTargetNotAuthorized("link")) {
            _ = try sandbox.resolve("link")
        }
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    @Test func rejectsSensitiveNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "KEY=1".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let sandbox = PathSandbox(root: root)
        #expect(throws: PathSandboxError.deniedSensitiveName(".env")) {
            _ = try sandbox.readText(".env")
        }
        try? FileManager.default.removeItem(at: root)
    }
}
