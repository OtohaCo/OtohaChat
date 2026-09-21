import AgentModels
import AgentTools
import Foundation

/// JSON Schema subset for host tool `input_schema` values sent to model APIs.
///
/// Anthropic Messages rejects unknown keys on `input_schema` (`additionalProperties`
/// among them) and some models reject an empty `required` array with HTTP 400.
/// Aliases belong in `properties`, not as free additional keys.
enum HostToolSchema {
    static func object(properties: [String: ToolSchema], required: Set<String> = []) -> ToolSchema {
        var json: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties.mapValues(\.json)),
        ]
        if !required.isEmpty {
            json["required"] = .array(required.sorted().map(JSONValue.string))
        }
        return ToolSchema(json: .object(json))
    }
}
