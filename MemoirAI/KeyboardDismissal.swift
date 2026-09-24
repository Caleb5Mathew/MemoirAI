import SwiftUI
import UIKit

private final class BackgroundKeyboardDismissRecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView || current is UIControl {
                return false
            }
            view = current.superview
        }
        return true
    }
}

private final class BackgroundKeyboardDismissInstallationView: UIView {
    weak var installer: BackgroundKeyboardDismissInstaller.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installer?.install(on: window)
    }
}

private struct BackgroundKeyboardDismissInstaller: UIViewRepresentable {
    final class Coordinator: NSObject {
        private let recognizerDelegate = BackgroundKeyboardDismissRecognizerDelegate()
        private weak var installedWindow: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        func install(on window: UIWindow?) {
            guard let window, installedWindow !== window else { return }
            uninstall()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = recognizerDelegate
            window.addGestureRecognizer(recognizer)
            installedWindow = window
            self.recognizer = recognizer
        }

        func uninstall() {
            if let recognizer, let installedWindow {
                installedWindow.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }

        @objc private func dismissKeyboard() {
            installedWindow?.endEditing(true)
        }

        deinit {
            uninstall()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = BackgroundKeyboardDismissInstallationView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.installer = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.install(on: uiView.window)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }
}

extension View {
    func dismissKeyboardOnBackgroundTap() -> some View {
        background {
            BackgroundKeyboardDismissInstaller()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
