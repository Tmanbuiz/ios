import UIKit
import Vision

// All rects in this file are normalized (0...1) with a top-left origin, relative to the screenshot.

struct RecognizedWord: Identifiable, Hashable {
    let id: Int          // reading order; also its index in `ScreenAnalysis.words`
    let text: String
    let rect: CGRect
    let line: Int
}

struct TextLine: Identifiable, Hashable {
    let id: Int
    let text: String
    let rect: CGRect
}

struct DetectedCode: Hashable {
    let payload: String
    let rect: CGRect
}

struct ScreenAnalysis {
    var words: [RecognizedWord] = []
    var lines: [TextLine] = []
    var objects: [CGRect] = []
    var codes: [DetectedCode] = []
    static let empty = ScreenAnalysis()
}

/// On-device understanding of the screenshot: every word (so you can tap or highlight text),
/// the main objects (so a tap selects a whole object), and QR/barcodes.
enum ImageAnalyzer {
    static func analyze(_ image: UIImage) async -> ScreenAnalysis {
        guard let cgImage = image.cgImage else { return .empty }
        return await Task.detached(priority: .userInitiated) {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.automaticallyDetectsLanguage = true
            let objectRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
            let codeRequest = VNDetectBarcodesRequest()

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try? handler.perform([textRequest, objectRequest, codeRequest])

            var result = ScreenAnalysis()
            for (lineIndex, observation) in (textRequest.results ?? []).enumerated() {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let string = candidate.string
                result.lines.append(TextLine(id: lineIndex, text: string, rect: flip(observation.boundingBox)))

                var ranges: [(String, Range<String.Index>)] = []
                string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byWords) { word, range, _, _ in
                    if let word { ranges.append((word, range)) }
                }
                for (word, range) in ranges {
                    guard let box = (try? candidate.boundingBox(for: range))?.boundingBox else { continue }
                    result.words.append(RecognizedWord(id: result.words.count, text: word, rect: flip(box), line: lineIndex))
                }
            }

            result.objects = (objectRequest.results?.first?.salientObjects ?? []).map { flip($0.boundingBox) }
            result.codes = (codeRequest.results ?? []).compactMap { code in
                code.payloadStringValue.map { DetectedCode(payload: $0, rect: flip(code.boundingBox)) }
            }
            return result
        }.value
    }

    /// Vision uses a bottom-left origin; SwiftUI uses top-left.
    private static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }
}
