import SwiftUI
import Translation

/// The bottom sheet that rises after a selection, like Google's results panel:
/// quick actions, an AI overview with sources, and a follow-up chat.
struct ResultsSheet: View {
    @ObservedObject var session: SearchSession
    @State private var followUp = ""
    @State private var browserURL: IdentifiedURL?
    @State private var showTranslate = false
    @State private var copied = false

    private static let smallDetent = PresentationDetent.fraction(0.45)

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        actions
                        if Config.aiEnabled {
                            ForEach(session.turns) { turn in
                                TurnView(turn: turn,
                                         isOverview: turn.id == session.turns.first(where: { !$0.isUser })?.id,
                                         open: { browserURL = IdentifiedURL(url: $0) })
                                    .id(turn.id)
                            }
                            if let error = session.errorText {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            noKeyNote
                        }
                    }
                    .padding(20)
                }
                .onChange(of: session.turns.count) {
                    if let id = session.turns.last?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
            if Config.aiEnabled { inputBar }
        }
        .presentationDetents([Self.smallDetent, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: Self.smallDetent))
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .translationPresentation(isPresented: $showTranslate, text: session.selectedText)
        .sheet(item: $browserURL) { WebSheet(url: $0.url) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(uiImage: session.croppedImage)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(session.overviewTitle ?? (session.isStreaming ? "Looking…" : "Your selection"))
                    .font(.title3.weight(.semibold))
                if !session.selectedText.isEmpty {
                    Text(session.selectedText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let text = session.selectedText
                if !text.isEmpty {
                    Chip(title: copied ? "Copied" : "Copy text", icon: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = text
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    Chip(title: "Translate", icon: "translate") { showTranslate = true }
                }
                if let code = session.selectedCode {
                    if let url = URL(string: code.payload), url.scheme?.hasPrefix("http") == true {
                        Chip(title: "Open QR link", icon: "qrcode") { browserURL = IdentifiedURL(url: url) }
                    } else {
                        Chip(title: "Copy QR text", icon: "qrcode") { UIPasteboard.general.string = code.payload }
                    }
                }
                let query = session.webQuery
                if !query.isEmpty, let url = Self.googleURL(query) {
                    Chip(title: "Search web", icon: "magnifyingglass") { browserURL = IdentifiedURL(url: url) }
                }
                ShareLink(item: Image(uiImage: session.croppedImage),
                          preview: SharePreview("Selection", image: Image(uiImage: session.croppedImage))) {
                    ChipLabel(title: "Share", icon: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noKeyNote: some View {
        Label("Add your Anthropic API key in Config.swift to get AI answers about your selection.",
              systemImage: "sparkles")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(session.turns.isEmpty ? "Ask about this image" : "Ask a follow-up",
                      text: $followUp, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
                .onSubmit(sendFollowUp)
            if session.isStreaming {
                Button { session.cancel() } label: {
                    Image(systemName: "stop.circle.fill").font(.largeTitle)
                }
            } else {
                Button(action: sendFollowUp) {
                    Image(systemName: "arrow.up.circle.fill").font(.largeTitle)
                }
                .disabled(followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func sendFollowUp() {
        let q = followUp
        followUp = ""
        session.send(q)
    }

    private static func googleURL(_ query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

// MARK: - Conversation turn

struct TurnView: View {
    let turn: ChatTurn
    let isOverview: Bool
    let open: (URL) -> Void

    var body: some View {
        if turn.isUser {
            HStack {
                Spacer(minLength: 40)
                Text(turn.text)
                    .padding(12)
                    .background(Palette.google[0].opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if isOverview {
                    Label("AI Overview", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if turn.searching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching the web…").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                let text = isOverview ? SearchSession.splitTitle(turn.text).body : turn.text
                if text.isEmpty && turn.streaming && !turn.searching {
                    // Google-style loading placeholder lines.
                    Text("Loading an overview of what you selected, with the key facts and links.")
                        .redacted(reason: .placeholder)
                } else if !text.isEmpty {
                    Text(markdown(text)).textSelection(.enabled)
                }
                if !turn.sources.isEmpty { sources }
            }
        }
    }

    private var sources: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(turn.sources.prefix(8))) { source in
                    Button { open(source.url) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title)
                                .font(.footnote.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(source.url.host() ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 160, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Chips

struct Chip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { ChipLabel(title: title, icon: icon) }
            .buttonStyle(.plain)
    }
}

struct ChipLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }
}
