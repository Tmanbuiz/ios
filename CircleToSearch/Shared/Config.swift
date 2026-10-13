import Foundation

enum Config {
    /// Optional Claude key baked in at build time (the GitHub build fills it from the ANTHROPIC_API_KEY secret).
    /// Usually you leave this alone and paste keys in the app's Settings instead.
    static let apiKey = "YOUR_ANTHROPIC_API_KEY"

    static var aiEnabled: Bool { !apiKey.isEmpty && apiKey != "YOUR_ANTHROPIC_API_KEY" }
}
