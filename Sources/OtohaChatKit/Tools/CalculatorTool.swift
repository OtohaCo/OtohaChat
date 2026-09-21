import AgentModels
import AgentTools
import Foundation

/// Restricted arithmetic. Tokens only; no shell, eval, or identifiers.
public struct CalculatorTool: AgentTool {
    public struct Input: Codable, Sendable {
        public var expression: String

        public init(expression: String) {
            self.expression = expression
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let candidates = [
                try container.decodeIfPresent(String.self, forKey: .expression),
                try container.decodeIfPresent(String.self, forKey: .formula),
                try container.decodeIfPresent(String.self, forKey: .input),
                try container.decodeIfPresent(String.self, forKey: .query),
            ]
            expression = candidates
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(expression, forKey: .expression)
        }

        private enum CodingKeys: String, CodingKey {
            case expression, formula, input, query
        }
    }

    public struct Output: Codable, Sendable {
        public var expression: String
        public var result: String
        public init(expression: String, result: String) {
            self.expression = expression
            self.result = result
        }
    }

    public static let name = "calculator"
    public static let description = "Evaluate a restricted arithmetic expression using + - * / ^ and parentheses. No variables or function calls."
    public static let inputSchema = ToolSchema.object(
        properties: [
            "expression": .string,
            "formula": .string,
            "input": .string,
            "query": .string,
        ],
        additionalProperties: true
    )
    public static let outputSchema = ToolSchema.object(
        properties: ["expression": .string, "result": .string],
        required: ["expression", "result"]
    )
    public let policy: ToolPolicy

    public init() throws {
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
        let expression = input.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            throw try RecoverableToolError(
                code: "missing_expression",
                message: "calculator requires an arithmetic expression in expression, formula, input, or query."
            )
        }
        do {
            let value = try RestrictedArithmetic.evaluate(expression)
            return ToolResult(output: .init(expression: expression, result: value))
        } catch {
            throw try RecoverableToolError(
                code: "invalid_expression",
                message: error.localizedDescription,
                details: .object(["expression": .string(expression)])
            )
        }
    }
}

public enum RestrictedArithmeticError: Error, Equatable, LocalizedError {
    case empty
    case invalidCharacter(Character)
    case syntax
    case divideByZero

    public var errorDescription: String? {
        switch self {
        case .empty: "Expression is empty."
        case .invalidCharacter(let character): "Unsupported character \(character)."
        case .syntax: "The expression could not be parsed."
        case .divideByZero: "Division by zero."
        }
    }
}

public enum RestrictedArithmetic {
    public static func evaluate(_ raw: String) throws -> String {
        let compact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { throw RestrictedArithmeticError.empty }
        for character in compact where !allowed.contains(character) {
            throw RestrictedArithmeticError.invalidCharacter(character)
        }
        var tokens = tokenize(compact)
        let value = try parseExpression(&tokens)
        guard tokens.isEmpty else { throw RestrictedArithmeticError.syntax }
        if value.isNaN || value.isInfinite { throw RestrictedArithmeticError.syntax }
        return format(value)
    }

    private static let allowed = Set("0123456789.+-*/^() ")

    private enum Token: Equatable {
        case number(Double)
        case plus, minus, star, slash, caret, lparen, rparen
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == " " {
                index = text.index(after: index)
                continue
            }
            if character.isNumber || character == "." {
                var end = index
                while end < text.endIndex, text[end].isNumber || text[end] == "." {
                    end = text.index(after: end)
                }
                tokens.append(.number(Double(text[index..<end]) ?? .nan))
                index = end
                continue
            }
            switch character {
            case "+": tokens.append(.plus)
            case "-": tokens.append(.minus)
            case "*": tokens.append(.star)
            case "/": tokens.append(.slash)
            case "^": tokens.append(.caret)
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            default: break
            }
            index = text.index(after: index)
        }
        return tokens
    }

    private static func parseExpression(_ tokens: inout [Token]) throws -> Double {
        var value = try parseTerm(&tokens)
        while let token = tokens.first {
            switch token {
            case .plus:
                tokens.removeFirst()
                value += try parseTerm(&tokens)
            case .minus:
                tokens.removeFirst()
                value -= try parseTerm(&tokens)
            default:
                return value
            }
        }
        return value
    }

    private static func parseTerm(_ tokens: inout [Token]) throws -> Double {
        var value = try parsePower(&tokens)
        while let token = tokens.first {
            switch token {
            case .star:
                tokens.removeFirst()
                value *= try parsePower(&tokens)
            case .slash:
                tokens.removeFirst()
                let divisor = try parsePower(&tokens)
                if divisor == 0 { throw RestrictedArithmeticError.divideByZero }
                value /= divisor
            default:
                return value
            }
        }
        return value
    }

    private static func parsePower(_ tokens: inout [Token]) throws -> Double {
        let base = try parseUnary(&tokens)
        if tokens.first == .caret {
            tokens.removeFirst()
            let exponent = try parsePower(&tokens)
            return pow(base, exponent)
        }
        return base
    }

    private static func parseUnary(_ tokens: inout [Token]) throws -> Double {
        if tokens.first == .minus {
            tokens.removeFirst()
            let value = try parseUnary(&tokens)
            return -value
        }
        if tokens.first == .plus {
            tokens.removeFirst()
            return try parseUnary(&tokens)
        }
        return try parsePrimary(&tokens)
    }

    private static func parsePrimary(_ tokens: inout [Token]) throws -> Double {
        guard let token = tokens.first else { throw RestrictedArithmeticError.syntax }
        switch token {
        case .number(let value):
            tokens.removeFirst()
            if value.isNaN { throw RestrictedArithmeticError.syntax }
            return value
        case .lparen:
            tokens.removeFirst()
            let value = try parseExpression(&tokens)
            guard tokens.first == .rparen else { throw RestrictedArithmeticError.syntax }
            tokens.removeFirst()
            return value
        default:
            throw RestrictedArithmeticError.syntax
        }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}
