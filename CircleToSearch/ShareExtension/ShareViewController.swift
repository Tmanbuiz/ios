import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Ask About This" in the share sheet: share any photo or screenshot and get the same
/// circle-to-search overlay without leaving the app you're in.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Task { await showOverlay() }
    }

    private func showOverlay() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
              let image = await loadImage(from: provider) else {
            close()
            return
        }
        let host = UIHostingController(rootView: SearchOverlayView(image: image) { [weak self] in self?.close() })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func loadImage(from provider: NSItemProvider) async -> UIImage? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        if let image = item as? UIImage { return image }
        if let url = item as? URL, let data = try? Data(contentsOf: url) { return UIImage(data: data) }
        if let data = item as? Data { return UIImage(data: data) }
        return nil
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
