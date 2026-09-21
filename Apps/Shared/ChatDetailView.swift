import OtohaChatKit
import SwiftUI

struct ChatDetailView: View {
    @EnvironmentObject private var store: ChatStore
    let conversationID: UUID
    @State private var input = ""
    @FocusState private var composerFocused: Bool

    private var conversation: ChatSessionSummary? {
        store.conversation(conversationID)
    }

    var body: some View {
        if let conversation {
            let isEmpty = conversation.snapshot.items.isEmpty
            ZStack {
                OtohaChatTheme.canvas
                VStack(spacing: 0) {
                    notices(conversation)
                    if isEmpty {
                        Spacer(minLength: 40)
                        Text("What should we do?")
                            .font(.system(size: 34, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .padding(.bottom, 28)
                        ComposerBar(
                            input: $input,
                            focused: $composerFocused,
                            conversation: conversation,
                            compact: false,
                            send: send,
                            stop: { Task { await store.stop(conversationID: conversationID) } }
                        )
                        .frame(maxWidth: 720)
                        .padding(.horizontal, 28)
                        Spacer()
                    } else {
                        TranscriptView(snapshot: conversation.snapshot, isBusy: conversation.snapshot.isBusy)
                        if conversation.configurationAppliesNext {
                            CopyableText(
                                text: "The selected model and reasoning apply to the next message. The active run is unchanged.",
                                font: .caption,
                                color: .secondary
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OtohaChatTheme.sidebar)
                        }
                        ComposerBar(
                            input: $input,
                            focused: $composerFocused,
                            conversation: conversation,
                            compact: true,
                            send: send,
                            stop: { Task { await store.stop(conversationID: conversationID) } }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle(isEmpty ? "" : conversation.title)
            #if os(macOS)
            .navigationSubtitle(isEmpty ? "" : conversation.modelName)
            #endif
        }
    }

    @ViewBuilder
    private func notices(_ conversation: ChatSessionSummary) -> some View {
        if store.banner != nil || conversation.availabilityMessage != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let banner = store.banner {
                    CopyableBanner(
                        text: banner,
                        systemImage: "info.circle",
                        tint: .orange,
                        font: .caption
                    )
                }
                if let note = conversation.availabilityMessage {
                    CopyableText(text: note, font: .caption, color: .secondary, showsCopyButton: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    private func send() {
        let submitted = input
        input = ""
        Task {
            await store.send(submitted, conversationID: conversationID)
            if let error = store.conversation(conversationID)?.inputError, !error.isEmpty {
                input = submitted
            }
        }
    }
}

private struct TranscriptView: View {
    let snapshot: ConversationSnapshot
    let isBusy: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(snapshot.items) { item in
                        TranscriptItemView(
                            item: item,
                            isGenerating: isBusy && isCurrentAssistant(item)
                        )
                            .id(item.id)
                    }
                    if let terminal = snapshot.terminal, snapshot.phase == .idle || snapshot.phase == .draining {
                        TerminalBanner(
                            terminal: terminal,
                            phase: snapshot.phase,
                            failureText: snapshot.runFailureText
                        )
                            .id("terminal-\(snapshot.generation)")
                    }
                    if let message = ExecutionReportCopy.message(for: snapshot.executionReport) {
                        CopyableBanner(
                            text: message,
                            systemImage: "checkmark.seal",
                            tint: .secondary,
                            font: .callout
                        )
                        .id("execution-report-\(snapshot.generation)")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
            .onChange(of: snapshot.generation) { _, _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: snapshot.items.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func isCurrentAssistant(_ item: ConversationItem) -> Bool {
        guard let currentID = snapshot.currentAssistantTurnID,
              case .assistant(let turn) = item else { return false }
        return turn.id == currentID
    }
}

private struct TranscriptItemView: View {
    let item: ConversationItem
    let isGenerating: Bool

    var body: some View {
        switch item {
        case .user(let message):
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy") { Clipboard.copy(message.text) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(OtohaChatTheme.chipFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .assistant(let turn):
            AssistantBubble(turn: turn, isGenerating: isGenerating)
        case .tool(let call):
            ToolCard(call: call)
        }
    }
}

private struct AssistantBubble: View {
    let turn: DisplayAssistantTurn
    let isGenerating: Bool

    var body: some View {
        if turn.text.isEmpty && turn.reasoning.isEmpty && !isGenerating {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !turn.reasoning.isEmpty {
                DisclosureGroup("Reasoning") {
                    Text(turn.reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("Copy") { Clipboard.copy(turn.reasoning) }
                        }
                }
            }
            if turn.text.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Answering…")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityLabel("Answering")
            } else {
                MarkdownMessage(text: turn.text)
            }
            if turn.usage.inputTokens != nil || turn.usage.outputTokens != nil {
                let usage = "Input \(turn.usage.inputTokens.map(String.init) ?? "—") · Output \(turn.usage.outputTokens.map(String.init) ?? "—")"
                Text(usage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy") { Clipboard.copy(usage) }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolCard: View {
    let call: DisplayToolCall
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(call.isError || call.state == .failed ? .orange : OtohaChatTheme.accent)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(call.name.isEmpty ? "Tool" : call.name)
                        .font(.subheadline.weight(.medium))
                        .textSelection(.enabled)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide tool details" : "Show tool details")
            }
            .contextMenu {
                Button("Copy") { Clipboard.copy(copyableToolSummary) }
            }
            if let failureText = call.failureText, !failureText.isEmpty {
                CopyableBanner(
                    text: failureText,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    font: .caption
                )
            }
            if expanded {
                if !call.argumentsJSON.isEmpty {
                    CopyableText(text: call.argumentsJSON, font: .caption.monospaced(), showsCopyButton: true)
                }
                if !call.resultText.isEmpty {
                    CopyableText(text: call.resultText, font: .caption, showsCopyButton: true)
                }
            }
        }
        .padding(10)
        .background(OtohaChatTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(call.name) \(status)")
    }

    private var copyableToolSummary: String {
        var lines = ["\(call.name.isEmpty ? "Tool" : call.name) — \(status)"]
        if let failureText = call.failureText, !failureText.isEmpty {
            lines.append(failureText)
        }
        if !call.argumentsJSON.isEmpty { lines.append(call.argumentsJSON) }
        if !call.resultText.isEmpty { lines.append(call.resultText) }
        return lines.joined(separator: "\n")
    }

    private var icon: String {
        if call.isError || call.state == .failed { return "exclamationmark.triangle.fill" }
        switch call.state {
        case .proposed: return "ellipsis.circle"
        case .admitted: return "gearshape.2"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var status: String {
        switch call.state {
        case .proposed: return "Proposed"
        case .admitted: return "Running"
        case .completed: return call.isError ? "Completed with an error" : "Completed"
        case .failed: return "Failed"
        }
    }
}

private struct TerminalBanner: View {
    let terminal: ConversationTerminal
    let phase: ConversationPhase
    let failureText: String?

    var body: some View {
        CopyableBanner(
            text: title,
            systemImage: icon,
            tint: color,
            font: .callout.weight(.medium)
        )
        .padding(.vertical, 4)
    }

    private var title: String {
        if phase == .draining { return "Cleaning up the previous run…" }
        switch terminal {
        case .completed: return "Run completed"
        case .refused: return "The model refused this request"
        case .incomplete: return "The response ended before completion"
        case .failed:
            return failureText ?? "The run failed; provisional output was not committed"
        case .cancelled: return "Run cancelled"
        }
    }

    private var icon: String {
        switch terminal {
        case .completed: "checkmark.circle.fill"
        case .refused: "hand.raised.fill"
        case .incomplete: "clock.badge.exclamationmark"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "stop.circle.fill"
        }
    }

    private var color: Color {
        switch terminal {
        case .completed: .green
        case .refused, .incomplete: .orange
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}
