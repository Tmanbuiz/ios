import SwiftUI
import Translation

/// Translates every line of text on the screen in place, like the Translate button in Circle to Search.
/// Runs fully on device with Apple's Translation framework (the first use may download a language).
struct ScreenTranslateLayer: View {
    let lines: [TextLine]
    let fit: CGRect

    @State private var translated: [Int: String] = [:]
    @State private var failed = false
    @State private var configuration: TranslationSession.Configuration? =
        TranslationSession.Configuration(target: Locale.current.language)

    var body: some View {
        ZStack {
            ForEach(lines) { line in
                if let text = translated[line.id] {
                    let r = toView(line.rect, fit)
                    Text(text)
                        .font(.system(size: max(8, r.height * 0.78)))
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .frame(width: r.width + 6, height: r.height + 2)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .position(x: r.midX, y: r.midY)
                }
            }
            if translated.isEmpty {
                Text(failed ? "Nothing to translate here" : "Translating…")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .allowsHitTesting(false)
        .translationTask(configuration) { session in
            let requests = lines.map {
                TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id))
            }
            do {
                for response in try await session.translations(from: requests) {
                    if let id = response.clientIdentifier.flatMap(Int.init) {
                        translated[id] = response.targetText
                    }
                }
            } catch {
                failed = true
            }
        }
    }
}
