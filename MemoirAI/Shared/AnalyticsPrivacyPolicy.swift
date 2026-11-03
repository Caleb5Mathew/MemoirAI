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
        "character_count", "generation_attempt", "page_count", "memory_count", "analytics_version", "preparation_attempt"
    ]

    private static let enumValues: [String: Set<String>] = [
        "screen": ["audience", "name", "record", "photo", "meetAlex", "cover", "spread", "illustration", "voice", "story", "building", "reveal", "home", "memories", "paywall", "settings", "login", "memory_detail", "memory_recording", "book", "profile", "chapter_journey", "profile_switcher", "book_editor", "book_library", "book_order", "profile_edit", "account_backup", "memory_rerecord", "memory_enhancement", "order_history", "order_detail", "memoir_chapters"],
        "diagnostic_reason": ["auth_unavailable", "recorder_start_rejected", "recorder_creation_failed"],
        "screen_exit_reason": ["navigation", "covered", "inactive", "identity_changed"],
        "action": ["continue", "back", "skip_tour", "record_start", "record_stop", "photo_skip", "reveal", "photo_camera", "photo_library", "play_sample", "pause_sample", "retry_generation", "retry_paywall", "retry_transcription", "continue_without_preview"],
        "input_readiness": ["empty", "too_short", "too_long", "needs_storyteller", "recording", "finalizing", "ready"],
        "input_method": ["none", "typing", "recording"],
        "field": ["narrator_name", "story"],
        "onboarding_version": ["native_v5", "native_v6", "native_v7"],
        "audience": ["myself", "someoneElse", "myChildren", "parentOrGrandparent", "notSure"],
        "storyteller": ["helper", "subject"],
        "purchase_origin": ["purchase", "restore"],
        "subscription_plan": ["yearly", "monthly"],
        "paywall_source": ["onboarding", "settings", "story_generation", "profile_limit", "memoir"],
        "failure_stage": ["auth", "recording", "preflight", "generation", "preparation", "purchase", "restore", "activation", "account_changed", "audio_file", "local_save", "playback", "share", "cloud_job", "finalization", "kickoff", "identity", "customer_info", "offerings", "packages", "trial_eligibility", "timeout", "image_download"],
        "onboarding_outcome": ["preview_unavailable", "offer_unavailable", "offer_presented", "entitled"],
        "permission_outcome": ["microphone_denied", "speech_denied", "granted"],
        "consent_outcome": ["accepted", "declined"],
        "failure_reason": ["cancelled", "network", "preview_response", "memory_preparation", "unknown", "authentication", "permission_denied", "precondition", "request_conflict", "account_changed", "quota_used", "attempts_exhausted", "rate_limited", "unavailable", "timeout", "server_error", "image_missing", "image_download"],
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
            if ["flow_id", "presentation_id", "generation_request_id"].contains(key) {
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
                return ["OnboardingPreviewServiceError", "NSError", "CancellationError", "URLError", "MemoryCreationError", "CloudTranscriptionError", "network", "configuration", "account_changed", "timeout", "unknown"].contains(kind)
            default:
                return false
            }
        }
    }
}
