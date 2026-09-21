import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Clipboard {
    static func copy(_ string: String) {
        guard !string.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

struct CopyableText: View {
    let text: String
    var font: Font = .body
    var color: Color = .primary
    var showsCopyButton: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsCopyButton {
                Button {
                    Clipboard.copy(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy")
            }
        }
        .contextMenu {
            Button("Copy") { Clipboard.copy(text) }
        }
    }
}

struct CopyableBanner: View {
    let text: String
    var systemImage: String
    var tint: Color = .red
    var font: Font = .callout.weight(.medium)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(font)
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Clipboard.copy(text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy")
        }
        .contextMenu {
            Button("Copy") { Clipboard.copy(text) }
        }
    }
}
