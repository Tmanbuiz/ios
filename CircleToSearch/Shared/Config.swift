import Foundation

enum Config {
    /// Leave as is to use the app without AI answers (text copy, translate, QR and web search still work).
    /// Paste a key from console.anthropic.com to turn on "Ask about this image".
    /// For an App Store build, point `endpoint` at your own server that adds the key, and leave `apiKey` empty.
    static let apiKey = "YOUR_ANTHROPIC_API_KEY"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-5-5"

    /// Lets Claude search the web so answers come with sources, like Google's AI Overview.
    static let useWebSearch = true
    /// Also sends a small copy of the whole screen so Claude knows what app the selection came from.
    static let sendFullScreenContext = true

    static var aiEnabled: Bool { !apiKey.isEmpty && apiKey != "YOUR_ANTHROPIC_API_KEY" }
}
