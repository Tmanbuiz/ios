import SwiftUI

/// The full-screen Circle to Search experience: the screen freezes, a color sweep runs across it,
/// and you circle, highlight (scribble over text) or tap anything to search it.
struct SearchOverlayView: View {
    @StateObject private var session: SearchSession
    @ObservedObject private var settings = AISettings.shared
    @State private var showSettings = false
    private let onClose: () -> Void

    @State private var stroke: [CGPoint] = []
    @State private var drawing = false
    @State private var strokeOpacity = 1.0
    @State private var shimmerY: CGFloat = -0.4
    @State private var showShimmer = true
    @State private var translateScreen = false
    @State private var question = ""
    @State private var selectionTick = 0
    @FocusState private var questionFocused: Bool

    init(image: UIImage, onClose: @escaping () -> Void) {
        _session = StateObject(wrappedValue: SearchSession(image: image))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()
            VStack {
                topBar
                Spacer()
                if !session.showResults { bottomBar }
            }
        }
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: selectionTick)
        .sheet(isPresented: $session.showResults) {
            ResultsSheet(session: session)
        }
        .fullScreenCover(isPresented: $showSettings) { SettingsView() }
        .task {
            withAnimation(.easeInOut(duration: 1.1)) { shimmerY = 1.4 }
            try? await Task.sleep(for: .seconds(1.1))
            showShimmer = false
        }
        .task { await session.analyze() }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let fit = fittedRect(session.image.size, in: geo.size)
            ZStack {
                Color.black
                Image(uiImage: session.image)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)

                if translateScreen {
                    ScreenTranslateLayer(lines: session.analysis.lines, fit: fit)
                }

                dimLayer(size: geo.size, fit: fit)
                wordHighlights(fit: fit)

                if showShimmer { shimmer(size: geo.size) }
                strokePath

                if let selection = session.selection, selection.kind == .region {
                    selectionFrame(toView(selection.rect, fit), fit: fit)
                }
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(fit: fit))
            .coordinateSpace(name: "canvas")
        }
    }

    /// Darkens the screen, leaving the selection bright.
    private func dimLayer(size: CGSize, fit: CGRect) -> some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            guard let selection = session.selection else { return }
            switch selection.kind {
            case .region:
                p.addRoundedRect(in: toView(selection.rect, fit), cornerSize: CGSize(width: 18, height: 18))
            case .text:
                for id in selection.wordIDs where session.analysis.words.indices.contains(id) {
                    let r = toView(session.analysis.words[id].rect, fit).insetBy(dx: -3, dy: -3)
                    p.addRoundedRect(in: r, cornerSize: CGSize(width: 4, height: 4))
                }
            }
        }
        .fill(Color.black.opacity(session.selection == nil ? 0.2 : 0.5), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func wordHighlights(fit: CGRect) -> some View {
        if let selection = session.selection, selection.kind == .text {
            ForEach(selection.wordIDs, id: \.self) { id in
                if session.analysis.words.indices.contains(id) {
                    let r = toView(session.analysis.words[id].rect, fit).insetBy(dx: -3, dy: -3)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.google[0].opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.google[0], lineWidth: 1.5))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func shimmer(size: CGSize) -> some View {
        LinearGradient(colors: [.clear] + Palette.google.map { $0.opacity(0.4) } + [.clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: size.width, height: size.height * 0.5)
            .position(x: size.width / 2, y: shimmerY * size.height)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private var strokePath: some View {
        Path { $0.addLines(stroke) }
            .stroke(LinearGradient(colors: Palette.google, startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            .shadow(color: .white.opacity(0.9), radius: 5)
            .opacity(strokeOpacity)
            .allowsHitTesting(false)
    }

    /// White corner brackets you can drag to resize the selection.
    private func selectionFrame(_ r: CGRect, fit: CGRect) -> some View {
        ZStack {
            CornerBrackets(length: min(30, r.width / 3, r.height / 3))
                .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.4), radius: 3)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)

            ForEach(Corner.allCases, id: \.self) { corner in
                Color.clear
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .position(corner.point(in: r))
                    .highPriorityGesture(
                        DragGesture(coordinateSpace: .named("canvas"))
                            .onChanged { v in resize(corner, to: toNorm(v.location, fit)) }
                            .onEnded { _ in
                                selectionTick += 1
                                session.startNewSearch(question: nil)
                            }
                    )
            }
        }
    }

    // MARK: Gestures

    private func drawGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !drawing {
                    drawing = true
                    stroke = [v.startLocation]
                    strokeOpacity = 1
                    questionFocused = false
                }
                stroke.append(v.location)
            }
            .onEnded { _ in
                drawing = false
                finishStroke(fit: fit)
                withAnimation(.easeOut(duration: 0.4)) { strokeOpacity = 0 }
            }
    }

    private func finishStroke(fit: CGRect) {
        let points = stroke.map { toNorm($0, fit) }
        guard let last = points.last else { return }
        let length = zip(stroke, stroke.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let picked = length < 12 ? selectionForTap(last, fit: fit) : selectionForStroke(points, fit: fit)
        selectionTick += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { session.selection = picked }
        session.startNewSearch(question: nil)
    }

    /// Tap: a word, else the object under your finger, else the area around it.
    private func selectionForTap(_ p: CGPoint, fit: CGRect) -> Selection {
        let a = session.analysis
        if let word = a.words.first(where: { $0.rect.insetBy(dx: -0.005, dy: -0.004).contains(p) }) {
            return Selection(kind: .text, rect: word.rect, wordIDs: [word.id])
        }
        if let object = a.objects.filter({ $0.contains(p) }).min(by: { $0.width * $0.height < $1.width * $1.height }) {
            return Selection(kind: .region, rect: object)
        }
        let w: CGFloat = 0.4, h = w * fit.width / fit.height
        return Selection(kind: .region, rect: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h).keptInUnit())
    }

    /// A flat swipe across words highlights them; any other shape (a circle, a scribble) selects the area it covers.
    private func selectionForStroke(_ points: [CGPoint], fit: CGRect) -> Selection {
        let xs = points.map(\.x), ys = points.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let words = session.analysis.words
        let hit = words.filter { w in
            let r = w.rect.insetBy(dx: -0.004, dy: -0.006)
            return points.contains { r.contains($0) }
        }
        if !hit.isEmpty, box.height * fit.height < 50 {
            let lo = hit.map(\.id).min()!, hi = hit.map(\.id).max()!
            let range = Array(words[lo...hi])
            let rect = range.dropFirst().reduce(range[0].rect) { $0.union($1.rect) }
            return Selection(kind: .text, rect: rect, wordIDs: range.map(\.id))
        }
        if box.width * fit.width < 20, box.height * fit.height < 20 {
            return selectionForTap(points.last!, fit: fit)
        }
        return Selection(kind: .region, rect: box.insetBy(dx: -0.015, dy: -0.01).intersection(.unit))
    }

    private func resize(_ corner: Corner, to p: CGPoint) {
        guard var selection = session.selection else { return }
        let minSide: CGFloat = 0.04
        let px = min(max(p.x, 0), 1), py = min(max(p.y, 0), 1)
        var x0 = selection.rect.minX, y0 = selection.rect.minY, x1 = selection.rect.maxX, y1 = selection.rect.maxY
        switch corner {
        case .topLeft: x0 = min(px, x1 - minSide); y0 = min(py, y1 - minSide)
        case .topRight: x1 = max(px, x0 + minSide); y0 = min(py, y1 - minSide)
        case .bottomLeft: x0 = min(px, x1 - minSide); y1 = max(py, y0 + minSide)
        case .bottomRight: x1 = max(px, x0 + minSide); y1 = max(py, y0 + minSide)
        }
        selection.rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        session.selection = selection
    }

    // MARK: Bars

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Button {
                withAnimation { translateScreen.toggle() }
            } label: {
                Label(translateScreen ? "Show original" : "Translate", systemImage: "translate")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .disabled(session.analysis.lines.isEmpty)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if session.selection == nil {
                Text("Circle, highlight or tap to search")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            if settings.isReady {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle").foregroundStyle(Palette.google[0])
                    TextField("Ask about your screen", text: $question)
                        .focused($questionFocused)
                        .submitLabel(.send)
                        .onSubmit(askAboutScreen)
                    Button(action: askAboutScreen) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(.regularMaterial, in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding()
    }

    private func askAboutScreen() {
        let q = question
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        question = ""
        questionFocused = false
        session.startNewSearch(question: q)   // about the selection if there is one, else the whole screen
    }
}

// MARK: - Shapes

enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    func point(in r: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }
}

struct CornerBrackets: Shape {
    var length: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = max(length, 1), c = min(14, l * 0.6)
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))

        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))

        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))

        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}
