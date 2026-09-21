import AgentCore
import AgentModels
import AgentProviders
import AgentTools
import Foundation

/// Deterministic provider used by tests, previews, and an explicit demo entry.
/// Ordinary user chat never falls back to this fixture.
public enum FixtureConversationRoute: String, CaseIterable, Equatable, Sendable {
    case direct
}

public enum FixtureConversationPacing: Equatable, Sendable {
    case immediate
    case visible

    var delay: Duration? {
        switch self {
        case .immediate: nil
        case .visible: .milliseconds(40)
        }
    }
}

public struct FixtureLaunchToken: Equatable, Sendable {
    public static let environmentKey = "OTOHACHAT_ENABLE_FIXTURE"
    public static let argument = "--fixture"

    public static func isEnabled(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains(argument) || environment[environmentKey] == "1"
    }
}

public func makeFixtureConversationController(
    conversationID: UUID = UUID(),
    sessionID: UUID? = nil,
    pacing: FixtureConversationPacing = .immediate,
    maxDisplayItems: Int = 100
) throws -> ConversationController {
    let model = ModelID(provider: StreamingFixtureProvider.providerID, name: "fixture-assistant")
    let provider = StreamingFixtureProvider(pacing: pacing)
    let agent = try Agent(
        model: model,
        provider: provider,
        tools: [try CalculatorTool(), try DateTimeTool()],
        configuration: .init(
            instructions: AppInstructions.base,
            maxModelTurns: 6,
            maxToolCalls: 4,
            runTimeout: .seconds(20)
        )
    )
    let session = try agent.makeSession(id: sessionID ?? conversationID)
    return ConversationController(
        conversationID: conversationID,
        session: AgentConversationSessionHandle(session: session),
        maxDisplayItems: maxDisplayItems
    )
}

struct StreamingFixtureProvider: ModelProvider {
    static let providerID = "applechat-fixture"

    let descriptor = ModelProviderDescriptor(
        id: providerID,
        capabilities: [.streaming, .multiTurn, .tools]
    )
    let pacing: FixtureConversationPacing

    func stream(request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        ModelEventStream.make { emit in
            let responseID = "fixture-\(request.runID?.uuidString ?? UUID().uuidString)-\(request.messages.count)"
            let info = ResponseInfo(id: responseID, model: request.model)
            try emit(.responseStarted(info))

            if case .tool(let result)? = request.messages.last {
                if lastUserText(in: request.messages).localizedCaseInsensitiveContains("fail after tool") {
                    try emit(.textDelta("The tool completed, but the final reply failed."))
                    throw ModelProviderError(
                        kind: .invalidResponse,
                        message: "Fixture protocol failure after tool."
                    )
                }
                let text = result.isError
                    ? "The tool reported an error."
                    : "Tool result received: \(renderContent(result.content))"
                try await emitText(text, info: info, stopReason: .endTurn, emit: emit)
                return
            }

            let prompt = lastUserText(in: request.messages)

            if prompt.localizedCaseInsensitiveContains("calculator")
                || prompt.contains("+")
                || prompt.contains("*")
                || prompt.localizedCaseInsensitiveContains("compute")
            {
                let expression = extractedExpression(from: prompt) ?? "2 + 2"
                let call = ToolCall(
                    id: .init(rawValue: "calc-\(request.runID?.uuidString ?? UUID().uuidString)"),
                    name: CalculatorTool.name,
                    argumentsJSON: #"{"expression":"\#(expression)"}"#,
                    completeness: .complete
                )
                try emitTool(call, info: info, emit: emit)
                return
            }

            if prompt.localizedCaseInsensitiveContains("date")
                || prompt.localizedCaseInsensitiveContains("time")
                || prompt.localizedCaseInsensitiveContains("timezone")
            {
                let call = ToolCall(
                    id: .init(rawValue: "dt-\(request.runID?.uuidString ?? UUID().uuidString)"),
                    name: DateTimeTool.name,
                    argumentsJSON: #"{"operation":"now","timezone":"UTC"}"#,
                    completeness: .complete
                )
                try emitTool(call, info: info, emit: emit)
                return
            }

            try await emitText("Fixture reply: \(prompt)", info: info, stopReason: .endTurn, emit: emit)
        }
    }

    private func emitTool(
        _ call: ToolCall,
        info: ResponseInfo,
        emit: @escaping ModelEventStream.Emit
    ) throws {
        try emit(.toolCallStarted(call.id, name: call.name))
        try emit(.toolCallArgumentsDelta(call.id, call.argumentsJSON))
        try emit(.toolCallCompleted(call))
        let usage = ModelUsage(inputTokens: 12, outputTokens: 5)
        try emit(.usage(usage))
        try emit(.responseCompleted(.init(
            info: info,
            toolCalls: [call],
            usage: usage,
            stopReason: .toolCalls
        )))
    }

    private func emitText(
        _ text: String,
        info: ResponseInfo,
        stopReason: StopReason,
        emit: @escaping ModelEventStream.Emit
    ) async throws {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            let separator = index == words.count - 1 ? "" : " "
            try emit(.textDelta(String(word) + separator))
            if let delay = pacing.delay {
                try await Task.sleep(for: delay)
            }
        }
        try emit(.usage(.init(inputTokens: 10, outputTokens: words.count)))
        try emit(.responseCompleted(.init(
            info: info,
            content: [.text(text)],
            usage: .init(inputTokens: 10, outputTokens: words.count),
            stopReason: stopReason
        )))
    }

    private func lastUserText(in messages: [ModelMessage]) -> String {
        messages.reversed().compactMap { message -> String? in
            guard case .user(let content) = message else { return nil }
            return content.compactMap { part -> String? in
                guard case .text(let text) = part else { return nil }
                return text
            }.joined()
        }.first ?? ""
    }

    private func extractedExpression(from prompt: String) -> String? {
        let allowed = CharacterSet(charactersIn: "0123456789+-*/().^ ")
        let scalars = prompt.unicodeScalars.filter { allowed.contains($0) }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
