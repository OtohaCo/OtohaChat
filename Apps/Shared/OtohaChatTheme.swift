import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum OtohaChatTheme {
    static let accent = Color(red: 0.18, green: 0.45, blue: 0.52)

    /// Light gray beside a white canvas. Dark mode uses a near-black so label colors stay readable.
    static let sidebar = Color.adaptive(
        light: RGB(0.973, 0.973, 0.976),
        dark: RGB(0.11, 0.11, 0.12)
    )

    static let canvas = Color.adaptive(
        light: RGB(1, 1, 1),
        dark: RGB(0, 0, 0)
    )

    /// Sits on the canvas. Light mode stays white; dark mode lifts off the black canvas.
    static let composerFill = Color.adaptive(
        light: RGB(1, 1, 1),
        dark: RGB(0.17, 0.17, 0.18)
    )

    static let composerStroke = Color.adaptive(
        light: RGB(0, 0, 0, 0.08),
        dark: RGB(1, 1, 1, 0.14)
    )

    static let chipFill = Color.primary.opacity(0.06)

    static let composerRadius: CGFloat = 26
    static let sendSize: CGFloat = 32
}

private struct RGB {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

extension Color {
    /// Resolves against the current appearance so fixed RGB values do not fight dark mode labels.
    fileprivate static func adaptive(light: RGB, dark: RGB) -> Color {
        #if os(macOS)
        let dynamic = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            let rgb = match == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
        }
        return Color(nsColor: dynamic)
        #else
        let dynamic = UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
        }
        return Color(uiColor: dynamic)
        #endif
    }
}
