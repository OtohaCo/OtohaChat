import AgentTools
import Foundation
import OtohaChatKit
import Testing

struct WorkspaceReadTests {
    @Test func listIncludesAgentsDirectoryAtWorkspaceRoot() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let sandbox = PathSandbox(root: root)
        let entries = try sandbox.list("")
        #expect(entries.contains(".agents"))
        #expect(entries.contains("readme.md"))
    }

    @Test func searchFindsSkillsByPathWithoutReadingNodeModules() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try WorkspaceReadTool(rootProvider: { root })
        let result = try await tool.execute(
            .init(operation: "search", query: "skills"),
            context: .init(sessionID: UUID(), runID: UUID(), callID: .init(rawValue: "search"))
        )
        #expect(result.output.matches.contains { $0.contains(".agents/skills/") })
        #expect(!result.output.matches.contains { $0.contains("node_modules") })
        #expect(!result.output.content.contains("truncated"))
    }

    @Test func searchStaysInsideOptionalPath() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try WorkspaceReadTool(rootProvider: { root })
        let result = try await tool.execute(
            .init(operation: "search", path: ".agents/skills", query: "docs-qa"),
            context: .init(sessionID: UUID(), runID: UUID(), callID: .init(rawValue: "scoped"))
        )
        #expect(result.output.matches.contains(".agents/skills/docs-qa/SKILL.md"))
        #expect(!result.output.matches.contains("readme.md"))
    }

    @Test func listSkillsFolderReturnsSkillFiles() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try WorkspaceReadTool(rootProvider: { root })
        let listed = try await tool.execute(
            .init(operation: "list", path: ".agents/skills"),
            context: .init(sessionID: UUID(), runID: UUID(), callID: .init(rawValue: "list"))
        )
        #expect(listed.output.matches.contains(".agents/skills/docs-qa"))
    }

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let skill = root.appendingPathComponent(".agents/skills/docs-qa")
        let buried = root.appendingPathComponent("node_modules/pkg")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: buried, withIntermediateDirectories: true)
        try "Use workspace_read.".write(
            to: skill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "this file says skills but lives in node_modules".write(
            to: buried.appendingPathComponent("hit.md"),
            atomically: true,
            encoding: .utf8
        )
        try "hello".write(to: root.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        return root
    }
}
