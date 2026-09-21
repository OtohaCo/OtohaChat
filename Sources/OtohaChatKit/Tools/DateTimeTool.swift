import AgentModels
import AgentTools
import Foundation

public struct DateTimeTool: AgentTool {
    public struct Input: Codable, Sendable {
        public var operation: String
        public var timezone: String?
        public var isoDate: String?
        public var days: Int?

        public init(operation: String, timezone: String? = nil, isoDate: String? = nil, days: Int? = nil) {
            self.operation = operation
            self.timezone = timezone
            self.isoDate = isoDate
            self.days = days
        }
    }

    public struct Output: Codable, Sendable {
        public var operation: String
        public var timezone: String
        public var result: String

        public init(operation: String, timezone: String, result: String) {
            self.operation = operation
            self.timezone = timezone
            self.result = result
        }
    }

    public static let name = "datetime"
    public static let description = "Read the current time in a named time zone, or add a day offset to an ISO-8601 date. Operations: now, add_days."
    public static let inputSchema = HostToolSchema.object(
        properties: [
            "operation": .string,
            "timezone": .string,
            "isoDate": .string,
            "days": .integer,
        ],
        required: ["operation"]
    )
    public static let outputSchema = ToolSchema.object(
        properties: [
            "operation": .string,
            "timezone": .string,
            "result": .string,
        ],
        required: ["operation", "timezone", "result"]
    )
    public let policy: ToolPolicy
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) throws {
        self.now = now
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
        let timezoneName = input.timezone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? TimeZone.current.identifier
        guard let timeZone = TimeZone(identifier: timezoneName) else {
            throw try RecoverableToolError(
                code: "unknown_timezone",
                message: "Unknown time zone \(timezoneName)."
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone

        switch input.operation {
        case "now":
            return ToolResult(output: .init(
                operation: "now",
                timezone: timezoneName,
                result: formatter.string(from: now())
            ))
        case "add_days":
            let base: Date
            if let isoDate = input.isoDate {
                guard let parsed = formatter.date(from: isoDate) ?? ISO8601DateFormatter().date(from: isoDate) else {
                    throw try RecoverableToolError(code: "invalid_date", message: "isoDate must be ISO-8601.")
                }
                base = parsed
            } else {
                base = now()
            }
            let days = input.days ?? 0
            guard let shifted = calendar.date(byAdding: .day, value: days, to: base) else {
                throw try RecoverableToolError(code: "invalid_date", message: "The date could not be shifted.")
            }
            return ToolResult(output: .init(
                operation: "add_days",
                timezone: timezoneName,
                result: formatter.string(from: shifted)
            ))
        default:
            throw try RecoverableToolError(
                code: "unsupported_operation",
                message: "operation must be now or add_days."
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
