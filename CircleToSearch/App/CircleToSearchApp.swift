import SwiftUI
import AppIntents
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Hand-off from Shortcuts

@MainActor
final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()

    struct Capture: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    @Published var capture: Capture?

    func open(_ image: UIImage) { capture = Capture(image: image) }
}

/// The Shortcut runs "Take Screenshot" and passes the result here, which opens the overlay instantly.
struct AskAboutScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Circle to Search"
    static var description = IntentDescription("Freeze the screen so you can circle, highlight or tap anything to search it.")
    static var openAppWhenRun = true

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        if let picture = UIImage(data: image.data) {
            CaptureStore.shared.open(picture)
        }
        return .result()
    }
}

struct CircleToSearchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskAboutScreenshotIntent(),
                    phrases: ["\(.applicationName) my screen"],
                    shortTitle: "Circle to Search",
                    systemImageName: "circle.dashed")
    }
}

// MARK: - App

@main
struct CircleToSearchApp: App {
    @StateObject private var store = CaptureStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                if let capture = store.capture {
                    SearchOverlayView(image: capture.image) { store.capture = nil }
                        .id(capture.id)
                        .transition(.opacity)
                }
            }
            .environmentObject(store)
            // Like Android, leaving the overlay ends the search.
            .onChange(of: scenePhase) {
                if scenePhase == .background { store.capture = nil }
            }
        }
    }
}

// MARK: - Home screen

struct HomeView: View {
    @EnvironmentObject private var store: CaptureStore
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 44))
                            .foregroundStyle(LinearGradient(colors: Palette.google, startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text("Search anything on your screen")
                            .font(.title2.weight(.bold))
                        Text("Double-tap the back of your iPhone or press the Action Button, then circle, highlight or tap what you want to know about.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Set up the trigger") {
                    Label("Shortcuts app: new shortcut with **Take Screenshot**, then **Circle to Search**", systemImage: "1.circle")
                    Label("Settings > Accessibility > Touch > Back Tap > Double Tap > your shortcut", systemImage: "2.circle")
                    Label("Or Settings > Action Button > Shortcut", systemImage: "3.circle")
                }

                Section {
                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Label("Try it on a screenshot", systemImage: "photo")
                    }
                } footer: {
                    Text(Config.aiEnabled ? "AI answers are on." : "AI answers are off until you add an API key in Config.swift. Everything else works without one.")
                }
            }
            .navigationTitle("Circle to Search")
        }
        .onChange(of: pickedItem) {
            guard let item = pickedItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    store.open(image)
                }
                pickedItem = nil
            }
        }
    }
}
