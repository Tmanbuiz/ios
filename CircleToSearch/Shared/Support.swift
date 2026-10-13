import SwiftUI
import UIKit
import WebKit

// MARK: - Geometry (normalized <-> on-screen)

func fittedRect(_ imageSize: CGSize, in container: CGSize) -> CGRect {
    let s = min(container.width / imageSize.width, container.height / imageSize.height)
    let w = imageSize.width * s, h = imageSize.height * s
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

func toView(_ n: CGRect, _ fit: CGRect) -> CGRect {
    CGRect(x: fit.minX + n.minX * fit.width, y: fit.minY + n.minY * fit.height,
           width: n.width * fit.width, height: n.height * fit.height)
}

func toNorm(_ p: CGPoint, _ fit: CGRect) -> CGPoint {
    CGPoint(x: (p.x - fit.minX) / fit.width, y: (p.y - fit.minY) / fit.height)
}

extension CGRect {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Slides the rect back inside 0...1 without changing its size (when it fits).
    func keptInUnit() -> CGRect {
        let w = min(width, 1), h = min(height, 1)
        return CGRect(x: min(max(0, minX), 1 - w), y: min(max(0, minY), 1 - h), width: w, height: h)
    }
}

// MARK: - Colors

enum Palette {
    static let google: [Color] = [
        Color(red: 0.26, green: 0.52, blue: 0.96),
        Color(red: 0.92, green: 0.26, blue: 0.21),
        Color(red: 0.98, green: 0.74, blue: 0.02),
        Color(red: 0.20, green: 0.66, blue: 0.33),
    ]
}

// MARK: - Images

extension UIImage {
    /// Redraws with .up orientation so pixel crops line up with what's on screen.
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Crops to a normalized rect. Expects an image that is already `.up`.
    func cropped(to n: CGRect) -> UIImage {
        guard let cg = cgImage else { return self }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let r = CGRect(x: n.minX * w, y: n.minY * h, width: n.width * w, height: n.height * h).integral
        guard let piece = cg.cropping(to: r) else { return self }
        return UIImage(cgImage: piece, scale: scale, orientation: .up)
    }

    func downscaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height) * scale
        guard longest > maxSide else { return self }
        let ratio = maxSide / longest
        let target = CGSize(width: size.width * scale * ratio, height: size.height * scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - Markdown

func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
}

// MARK: - In-app browser (works inside the share extension too)

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct WebSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BrowserView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host() ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

struct BrowserView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
