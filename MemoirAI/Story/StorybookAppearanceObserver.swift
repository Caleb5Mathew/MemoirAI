import SwiftUI
import UIKit

/// SwiftUI's onAppear runs during a push. Book restoration must wait until
/// UIKit finishes presenting the destination so decoding cannot stall the slide.
struct StorybookAppearanceObserver: UIViewControllerRepresentable {
    let onFirstAppearance: () -> Void

    func makeUIViewController(context: Context) -> StorybookAppearanceController {
        let controller = StorybookAppearanceController()
        controller.onFirstAppearance = onFirstAppearance
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: StorybookAppearanceController, context: Context) {
        controller.onFirstAppearance = onFirstAppearance
    }
}

final class StorybookAppearanceController: UIViewController {
    var onFirstAppearance: (() -> Void)?
    private var didStart = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        onFirstAppearance?()
    }
}
