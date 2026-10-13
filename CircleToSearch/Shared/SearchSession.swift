import SwiftUI

struct Selection: Equatable {
    enum Kind { case region, text }
    var kind: Kind
    var rect: CGRect            // normalized, top-left origin
    var wordIDs: [Int] = []     // for text selections, in reading order
}

struct ChatTurn: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String
    var sources: [Source] = []
    var searching = false
    var streaming = false
}

/// Everything about one Circle to Search session: the frozen screenshot, what's selected,
/// and the conversation with Claude about it.
@MainActor
final class SearchSession: ObservableObject {
    let image: UIImage
    @Published var analysis = ScreenAnalysis.empty
    @Published var selection: Selection?
    @Published var turns: [ChatTurn] = []
    @Published var showResults = false
    @Published var isStreaming = false
    @Published var errorText: String?

    private var history: [AIMessage] = []
    private let settings = AISettings.shared

    /// Which AI answered, shown in the results sheet.
    @Published private(set) var answeredBy: AIProvider?
    private var streamTask: Task<Void, Never>?
    private var generation = 0

    init(image: UIImage) {
        self.image = image.normalized()
    }

    func analyze() async {
        analysis = await ImageAnalyzer.analyze(image)
    }

    // MARK: What's selected

    var selectedText: String {
        guard let selection else { return "" }
        let words: [RecognizedWord]
        if selection.kind == .text {
            words = selection.wordIDs.compactMap { analysis.words.indices.contains($0) ? analysis.words[$0] : nil }
        } else {
            words = analysis.words.filter { selection.rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
        }
        var out = ""
        var lastLine: Int?
        for word in words {
            if let lastLine { out += lastLine == word.line ? " " : "\n" }
            out += word.text
            lastLine = word.line
        }
        return out
    }

    var selectedCode: DetectedCode? {
        guard let selection else { return nil }
        return analysis.codes.first { selection.rect.intersects($0.rect) }
    }

    var croppedImage: UIImage {
        selection.map { image.cropped(to: $0.rect) } ?? image
    }

    var overviewTitle: String? {
        turns.first { !$0.isUser }.flatMap { Self.splitTitle($0.text).title }
    }

    /// What "Search web" looks up: the selected text, else what Claude identified, else the question.
    var webQuery: String {
        let text = selectedText.replacingOccurrences(of: "\n", with: " ")
        if !text.isEmpty { return String(text.prefix(150)) }
        return overviewTitle ?? turns.first(where: \.isUser)?.text ?? ""
    }

    // MARK: Asking Claude

    /// Starts over for a new selection (or a question about the whole screen).
    func startNewSearch(question: String?) {
        cancel()
        history = []
        turns = []
        errorText = nil
        showResults = true
        if settings.isReady { send(question) }
    }

    func send(_ question: String?) {
        guard settings.isReady, !isStreaming else { return }
        let q = (question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if history.isEmpty {
            var images = [Self.jpeg(croppedImage, maxSide: 1568)]
            if settings.sendFullScreen, selection != nil { images.append(Self.jpeg(image, maxSide: 1024)) }
            var prompt = q.isEmpty ? "What is this? Give me a quick overview." : q
            let text = selectedText
            if !text.isEmpty { prompt += "\n\nText detected in my selection:\n\(text)" }
            history.append(AIMessage(isUser: true, text: prompt, images: images))
        } else {
            guard !q.isEmpty else { return }
            history.append(AIMessage(isUser: true, text: q))
        }

        if !q.isEmpty { turns.append(ChatTurn(isUser: true, text: q)) }
        turns.append(ChatTurn(isUser: false, text: "", streaming: true))
        let index = turns.count - 1
        let gen = generation
        let messages = history
        let provider = settings.provider
        let options = AIClient.Options(provider: provider,
                                       key: settings.key(for: provider),
                                       model: settings.model(for: provider),
                                       webSearch: settings.useWebSearch && provider.searchesWeb)
        answeredBy = provider
        showResults = true
        isStreaming = true
        errorText = nil

        streamTask = Task { [weak self] in
            var answer = ""
            var failure: String?
            var refused = false
            do {
                for try await event in AIClient.stream(messages, options: options) {
                    guard let self, self.generation == gen else { return }
                    switch event {
                    case .text(let t):
                        answer += t
                        self.turns[index].text = answer
                        self.turns[index].searching = false
                    case .searching:
                        self.turns[index].searching = true
                    case .source(let source):
                        if !self.turns[index].sources.contains(source) { self.turns[index].sources.append(source) }
                    case .refused:
                        refused = true
                    }
                }
            } catch {
                failure = error.localizedDescription
            }
            guard let self, self.generation == gen else { return }
            if refused { failure = "\(provider.name) couldn't answer this one. Try selecting something else." }
            self.finish(index: index, answer: refused ? "" : answer, failure: failure)
        }
    }

    func cancel() {
        guard isStreaming else { return }
        streamTask?.cancel()
        generation += 1
        isStreaming = false
        if let i = turns.lastIndex(where: { !$0.isUser }) {
            turns[i].streaming = false
            turns[i].searching = false
            let partial = turns[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if partial.isEmpty { history.removeLast() } else { history.append(AIMessage(isUser: false, text: partial)) }
        }
    }

    private func finish(index: Int, answer: String, failure: String?) {
        isStreaming = false
        turns[index].streaming = false
        turns[index].searching = false
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if failure == nil, !trimmed.isEmpty {
            history.append(AIMessage(isUser: false, text: trimmed))
        } else {
            history.removeLast()   // drop the unanswered question so the conversation stays valid
            turns[index].text = trimmed
            errorText = failure ?? "No answer came back. Try again."
        }
    }

    // MARK: Helpers

    static func splitTitle(_ text: String) -> (title: String?, body: String) {
        var lines = text.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { $0.hasPrefix("# ") }) else { return (nil, text) }
        let title = String(lines[i].dropFirst(2)).trimmingCharacters(in: .whitespaces)
        lines.remove(at: i)
        return (title, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func jpeg(_ image: UIImage, maxSide: CGFloat) -> Data {
        image.downscaled(maxSide: maxSide).jpegData(compressionQuality: 0.85) ?? Data()
    }
}
