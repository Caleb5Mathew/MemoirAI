import Foundation
import Mixpanel

enum AnalyticsPrivacyPolicy {
    private static let booleanKeys: Set<String> = [
        "has_audio", "has_text", "has_photos", "has_custom_prompt",
        "voice_available", "is_completed", "has_headshot", "cached"
    ]
    private static let countKeys: Set<String> = [
        "characters_saved", "chapter_number", "per_child_count", "turns",
        "characters_extracted", "step", "duration_ms", "step_duration_ms",
        "character_count", "generation_attempt", "page_count", "memory_count"
    ]

    private static let enumValues: [String: Set<String>] = [
        "screen": ["audience", "name", "record", "photo", "meetAlex", "cover", "spread", "illustration", "voice", "story", "building", "reveal", "home", "memories", "paywall", "settings", "login", "memory_detail", "memory_recording", "book", "profile", "chapter_journey", "profile_switcher", "book_editor", "book_library", "book_order", "profile_edit", "account_backup", "memory_rerecord", "memory_enhancement", "order_history", "order_detail", "memoir_chapters"],
        "diagnostic_reason": ["auth_unavailable", "recorder_start_rejected", "recorder_creation_failed"],
        "screen_exit_reason": ["navigation", "covered", "inactive", "identity_changed"],
        "action": ["continue", "back", "skip_tour", "sample_answer", "record_start", "record_stop", "photo_skip", "reveal", "photo_camera", "photo_library", "play_sample", "pause_sample", "retry_generation", "retry_paywall", "retry_transcription"],
        "field": ["narrator_name", "story"],
        "onboarding_version": ["native_v5"],
        "audience": ["myself", "someoneElse", "myChildren", "parentOrGrandparent", "notSure"],
        "storyteller": ["helper", "subject"],
        "purchase_origin": ["purchase", "restore"],
        "failure_stage": ["auth", "recording", "preflight", "generation", "preparation", "purchase", "restore", "activation", "account_changed", "audio_file", "local_save", "playback", "share", "cloud_job", "finalization", "kickoff"],
        "dismissal_reason": ["external", "close_button", "entitlement_active"],
        "tab": ["home", "memories", "storybook", "profile", "memoir"],
        "save_scope": ["local"],
        "playback_source": ["local", "remote"],
        "provider": ["apple", "google", "email", "unknown"],
        "auth_operation": ["sign_in", "create_account", "link_account"],
        "auth_outcome": ["success", "failure"]
    ]

    static func isAllowedScreen(_ screen: String) -> Bool {
        enumValues["screen"]?.contains(screen) == true
    }

    static func sanitized(_ properties: Properties) -> Properties {
        properties.filter { key, value in
            if booleanKeys.contains(key) { return value is Bool }
            if countKeys.contains(key) {
                guard let count = value as? Int else { return false }
                return count >= 0
            }
            if let allowed = enumValues[key] {
                guard let value = value as? String else { return false }
                return allowed.contains(value)
            }
            if ["flow_id", "presentation_id"].contains(key) {
                guard let value = value as? String else { return false }
                return UUID(uuidString: value) != nil
            }
            switch key {
            case "recording_duration":
                guard let duration = value as? Double else { return false }
                return duration.isFinite && duration >= 0
            case "source":
                guard let source = value as? String else { return false }
                return ["camera", "library"].contains(source)
            case "failure_kind":
                guard let kind = value as? String else { return false }
                return ["OnboardingPreviewServiceError", "NSError", "CancellationError", "URLError", "MemoryCreationError"].contains(kind)
            default:
                return false
            }
        }
    }
}
