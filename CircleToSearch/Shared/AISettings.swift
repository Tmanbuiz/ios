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
        let saved = defaults.string(forKey: "key.\(p.rawValue)") ?? ""
        if saved.isEmpty, p == .claude, Config.aiEnabled { return Config.apiKey }   // key baked in at build time
        return saved
    }

    func setKey(_ key: String, for p: AIProvider) {
        objectWillChange.send()
        defaults.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "key.\(p.rawValue)")
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
                    SecureField("Paste your \(settings.provider.company) API key",
                                text: Binding(get: { settings.key(for: settings.provider) },
                                              set: { settings.setKey($0, for: settings.provider) }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
