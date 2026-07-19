import UIKit

/// Centralized semantic haptic feedback. Generators are created once and kept
/// prepared so the first fire has no latency. All methods must be called from the
/// main thread (UIFeedbackGenerator requirement); every current call site is view
/// code or a MainActor-isolated handler.
enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Call once around app launch so the first real haptic is instant.
    static func warmUp() {
        lightImpact.prepare()
        mediumImpact.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// Primary button presses and deliberate actions (start recording, save).
    static func tap() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    /// Lightweight state changes: tab switches, pause/resume, toggles, pickers.
    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Something the user was waiting for finished well (generation done, order placed).
    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }

    /// Page settle in book views.
    static func pageTurn() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    /// Escape hatch for migrating existing ad hoc call sites without changing feel.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:
            lightImpact.impactOccurred()
            lightImpact.prepare()
        case .heavy:
            heavyImpact.impactOccurred()
            heavyImpact.prepare()
        default:
            mediumImpact.impactOccurred()
            mediumImpact.prepare()
        }
    }
}
