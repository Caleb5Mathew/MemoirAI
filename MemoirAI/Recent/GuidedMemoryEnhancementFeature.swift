import Foundation

/// Feature gate for voice-first guided memory enhancement (`Enhance` flow).
/// Toggle with `UserDefaults` key for rollout; default `true` so guided is the primary path.
enum GuidedMemoryEnhancementFeature {
    static let userDefaultsKey = "guidedMemoryEnhancementEnabled"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }
}
