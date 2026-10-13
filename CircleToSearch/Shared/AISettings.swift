import SwiftUI

enum AIProvider: String, CaseIterable, Identifiable {
    case claude, chatgpt, gemini, grok

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        }
    }

    var company: String {
        switch self {
        case .claude: return "Anthropic"
        case .chatgpt: return "OpenAI"
        case .gemini: return "Google"
        case .grok: return "xAI"
        }
    }

    /// Editable in Settings, since providers release new models often.
    var defaultModel: String {
        switch self {
        case .claude: return "claude-opus-5-5"
        case .chatgpt: return "gpt-5"
        case .gemini: return "gemini-2.5-flash"
        case .grok: return "grok-4"
        }
    }

    var keyPage: URL {
        switch self {
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .chatgpt: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")!
        case .grok: return URL(string: "https://console.x.ai")!
        }
    }

    var icon: String {
        switch self {
        case .claude: return "sparkle"
        case .chatgpt: return "bubble.left.and.text.bubble.right"
        case .gemini: return "sparkles"
        case .grok: return "bolt.fill"
        }
    }

    /// Whether answers can include web sources.
    var searchesWeb: Bool { self == .claude || self == .gemini }
}

/// Settings shared by the app and the share extension (through an App Group when the build has one).
@MainActor
final class AISettings: ObservableObject {
    static let shared = AISettings()
    static let appGroup = "group.com.example.circletosearch"

    private let defaults = UserDefaults(suiteName: AISettings.appGroup) ?? .standard

    @Published var provider: AIProvider { didSet { defaults.set(provider.rawValue, forKey: "provider") } }
    @Published var useWebSearch: Bool { didSet { defaults.set(useWebSearch, forKey: "useWebSearch") } }
    @Published var sendFullScreen: Bool { didSet { defaults.set(sendFullScreen, forKey: "sendFullScreen") } }

    private init() {
        provider = AIProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .claude
        useWebSearch = defaults.object(forKey: "useWebSearch") as? Bool ?? true
        sendFullScreen = defaults.object(forKey: "sendFullScreen") as? Bool ?? true
    }

    func key(for p: AIProvider) -> String {
        let saved = Self.cleanKey(defaults.string(forKey: "key.\(p.rawValue)") ?? "")
        if saved.isEmpty, p == .claude, Config.aiEnabled { return Config.apiKey }   // key baked in at build time
        return saved
    }

    func setKey(_ key: String, for p: AIProvider) {
        objectWillChange.send()
        defaults.set(Self.cleanKey(key), forKey: "key.\(p.rawValue)")
    }

    /// API keys are plain ASCII with no spaces. Pasting from notes, email or a web page can bring along
    /// spaces, line breaks, zero-width characters or smart quotes that make the provider reject the key.
    static func cleanKey(_ key: String) -> String {
        String(String.UnicodeScalarView(key.unicodeScalars.filter { (0x21...0x7E).contains($0.value) && $0 != "\"" && $0 != "'" }))
    }

    /// e.g. "xai-AbC…9xYz · 84 characters", so you can compare it with the key in your provider's console.
    static func preview(_ key: String) -> String {
        guard key.count > 10 else { return key.isEmpty ? "No key saved" : "\(key.count) characters" }
        return "\(key.prefix(7))…\(key.suffix(4)) · \(key.count) characters"
    }

    func model(for p: AIProvider) -> String {
        let saved = defaults.string(forKey: "model.\(p.rawValue)") ?? ""
        return saved.isEmpty ? p.defaultModel : saved
    }

    func setModel(_ model: String, for p: AIProvider) {
        objectWillChange.send()
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "model.\(p.rawValue)")
    }

    var isReady: Bool { !key(for: provider).isEmpty }
}

// MARK: - Settings screen

struct SettingsView: View {
    @ObservedObject private var settings = AISettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var browserURL: IdentifiedURL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AIProvider.allCases) { p in
                        Button {
                            settings.provider = p
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: p.icon)
                                    .frame(width: 28)
                                    .foregroundStyle(Palette.google[AIProvider.allCases.firstIndex(of: p)! % 4])
                                VStack(alignment: .leading) {
                                    Text(p.name).foregroundStyle(.primary)
                                    Text(settings.key(for: p).isEmpty ? "\(p.company) · no key yet" : "\(p.company) · key added")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.provider == p {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.google[0])
                                }
                            }
                        }
                    }
                } header: {
                    Text("AI assistant")
                } footer: {
                    Text("Copy text, translate, QR codes and web search work without any key.")
                }

                Section {
                    KeyEditor(provider: settings.provider)
                    Button("Get a \(settings.provider.name) API key") {
                        browserURL = IdentifiedURL(url: settings.provider.keyPage)
                    }
                    LabeledContent("Model") {
                        TextField(settings.provider.defaultModel,
                                  text: Binding(get: { settings.model(for: settings.provider) },
                                                set: { settings.setModel($0, for: settings.provider) }))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("\(settings.provider.name) settings")
                } footer: {
                    Text("Your key stays on this phone and is only sent to \(settings.provider.company).")
                }

                Section("Answers") {
                    Toggle("Search the web for sources", isOn: $settings.useWebSearch)
                        .disabled(!settings.provider.searchesWeb)
                    Toggle("Include the whole screen for context", isOn: $settings.sendFullScreen)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $browserURL) { WebSheet(url: $0.url) }
        }
    }
}

// MARK: - Key field

/// Paste, show/hide, preview and test the key for one provider.
struct KeyEditor: View {
    let provider: AIProvider
    @ObservedObject private var settings = AISettings.shared
    @State private var reveal = false
    @State private var testing = false
    @State private var testResult: (ok: Bool, message: String)?

    var body: some View {
        let key = Binding(get: { settings.key(for: provider) },
                          set: { settings.setKey($0, for: provider); testResult = nil })
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Group {
                    if reveal {
                        TextField("Paste your \(provider.company) API key", text: key)
                    } else {
                        SecureField("Paste your \(provider.company) API key", text: key)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.none)
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless)
            }
            Text(AISettings.preview(settings.key(for: provider)))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Paste") {
                    if let text = UIPasteboard.general.string { key.wrappedValue = text }
                }
                Button("Clear", role: .destructive) { key.wrappedValue = "" }
                Spacer()
                Button {
                    Task {
                        testing = true
                        testResult = await AIClient.testKey(provider: provider, key: settings.key(for: provider))
                        testing = false
                    }
                } label: {
                    if testing { ProgressView() } else { Text("Test key") }
                }
                .disabled(settings.key(for: provider).isEmpty || testing)
            }
            .buttonStyle(.bordered)
            if let testResult {
                Label(testResult.message, systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.footnote)
                    .foregroundStyle(testResult.ok ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}
