import Foundation

/// Apple on-device and PCC models share a small context window. Reserving the
/// host's cloud default (4096 output tokens) leaves no room for instructions,
/// tools, or a follow-up turn.
public enum AppleGenerationLimits {
    public static let maximumResponseTokens = 1_024

    public static func responseTokens(requested: Int) -> Int {
        min(max(requested, 1), maximumResponseTokens)
    }
}
