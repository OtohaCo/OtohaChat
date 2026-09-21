import SwiftUI

struct MarkdownMessage: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value):
                    Text(parseMarkdown(value))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let value):
                    CodeBlockView(language: language, code: value)
                }
            }
        }
    }

    private var blocks: [MarkdownBlock] {
        MarkdownSplitter.split(text)
    }

    private func parseMarkdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }
}

private enum MarkdownBlock {
    case text(String)
    case code(String, String)
}

private enum MarkdownSplitter {
    static func split(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var remainder = text[...]
        while let start = remainder.range(of: "```") {
            let before = String(remainder[..<start.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(before))
            }
            remainder = remainder[start.upperBound...]
            let languageLineEnd = remainder.firstIndex(of: "\n") ?? remainder.endIndex
            let language = String(remainder[..<languageLineEnd]).trimmingCharacters(in: .whitespaces)
            remainder = languageLineEnd < remainder.endIndex ? remainder[remainder.index(after: languageLineEnd)...] : remainder[languageLineEnd...]
            if let end = remainder.range(of: "```") {
                blocks.append(.code(language, String(remainder[..<end.lowerBound])))
                remainder = remainder[end.upperBound...]
            } else {
                blocks.append(.code(language, String(remainder)))
                remainder = remainder[remainder.endIndex...]
            }
        }
        let tail = String(remainder)
        if !tail.isEmpty { blocks.append(.text(tail)) }
        if blocks.isEmpty { blocks.append(.text(text)) }
        return blocks
    }
}

private struct CodeBlockView: View {
    let language: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(language.isEmpty ? "Code" : language)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    Clipboard.copy(code)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .accessibilityLabel("Copy code")
            }
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
