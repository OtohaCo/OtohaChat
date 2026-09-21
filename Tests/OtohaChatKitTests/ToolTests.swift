import OtohaChatKit
import Foundation
import Testing

struct CalculatorAndNotesTests {
    @Test func calculatorEvaluatesRestrictedArithmetic() throws {
        #expect(try RestrictedArithmetic.evaluate("2 + 3 * 4") == "14")
        #expect(try RestrictedArithmetic.evaluate("(2 + 3) * 4") == "20")
        #expect(throws: RestrictedArithmeticError.divideByZero) {
            _ = try RestrictedArithmetic.evaluate("1/0")
        }
        #expect(throws: RestrictedArithmeticError.self) {
            _ = try RestrictedArithmetic.evaluate("os.system")
        }
    }

    @Test func calculatorAcceptsFormulaAndInputAliases() throws {
        let decoded = try JSONDecoder().decode(
            CalculatorTool.Input.self,
            from: Data(#"{"formula":"1+2","note":"claude extra"}"#.utf8)
        )
        #expect(decoded.expression == "1+2")
        let fromInput = try JSONDecoder().decode(
            CalculatorTool.Input.self,
            from: Data(#"{"input":"  2 + 2  "}"#.utf8)
        )
        #expect(fromInput.expression == "2 + 2")
        #expect(try RestrictedArithmetic.evaluate(fromInput.expression) == "4")
    }

    @Test func notesRejectStaleRevisionAndKeepReceiptFromStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try FileNotesStore(directory: directory)
        let created = try store.upsert(id: "alpha", title: "One", body: "Hello", expectedRevision: nil)
        #expect(throws: NotesStoreError.revisionConflict(created.revision)) {
            _ = try store.upsert(id: "alpha", title: "Two", body: "Nope", expectedRevision: "stale")
        }
        let updated = try store.upsert(id: "alpha", title: "Two", body: "OK", expectedRevision: created.revision)
        #expect(updated.revision != created.revision)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func datetimeNowUsesRequestedTimeZone() async throws {
        let tool = try DateTimeTool(now: { Date(timeIntervalSince1970: 0) })
        let result = try await tool.execute(
            .init(operation: "now", timezone: "UTC"),
            context: .init(sessionID: UUID(), runID: UUID(), callID: .init(rawValue: "dt"))
        )
        #expect(result.output.timezone == "UTC")
        #expect(result.output.result.contains("1970"))
    }
}
