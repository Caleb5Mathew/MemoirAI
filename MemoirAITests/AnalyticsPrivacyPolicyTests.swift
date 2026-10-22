import Foundation
import Mixpanel
import Testing
@testable import MemoirAI

struct AnalyticsPrivacyPolicyTests {
    @Test func removesMemoirContentAndIdentifiersFromAnalytics() {
        let properties: Properties = [
            "memory_id": "private-memory-id",
            "prompt_text": "private memoir prompt",
            "has_audio": true
        ]

        let sanitized = AnalyticsPrivacyPolicy.sanitized(properties)

        #expect(sanitized["memory_id"] == nil)
        #expect(sanitized["prompt_text"] == nil)
        #expect(sanitized["has_audio"] != nil)
    }

    @Test func rejectsUnknownPropertiesAndPrivateValuesUnderAllowedKeys() {
        let sanitized = AnalyticsPrivacyPolicy.sanitized([
            "transcript": "private memory", "photo_url": "https://private.example/photo",
            "raw_token": "private token", "has_audio": "private story",
            "characters_saved": "private story", "source": "relative's name",
            "failure_kind": "private error message", "recording_duration": Double.infinity
        ])
        #expect(sanitized.isEmpty)
    }

    @Test func retainsAuditedCoarseMetrics() {
        let properties: Properties = [
            "has_audio": true, "has_text": false, "has_photos": true,
            "recording_duration": 12.5, "characters_saved": 40, "step": 3,
            "source": "camera", "failure_kind": "OnboardingPreviewServiceError",
            "duration_ms": 1500, "has_headshot": false, "cached": true
        ]
        #expect(AnalyticsPrivacyPolicy.sanitized(properties).count == properties.count)
    }

    @Test func allowsBoundedScreenTimingWithoutAcceptingPrivateLabels() {
        #expect(AnalyticsPrivacyPolicy.isAllowedScreen("memory_detail"))
        #expect(!AnalyticsPrivacyPolicy.isAllowedScreen("My private memory"))
        let safe = AnalyticsPrivacyPolicy.sanitized([
            "screen": "book", "screen_exit_reason": "covered", "duration_ms": 1200
        ])
        #expect(safe.count == 3)
        #expect(AnalyticsPrivacyPolicy.sanitized([
            "screen_exit_reason": "private error or name"
        ]).isEmpty)
    }

    @Test func retainsRetryDiagnosticsButRejectsRawErrorMessages() {
        let safe = AnalyticsPrivacyPolicy.sanitized([
            "screen": "memory_recording", "action": "retry_transcription",
            "failure_stage": "recording", "diagnostic_reason": "recorder_start_rejected"
        ])
        #expect(safe.count == 4)
        #expect(AnalyticsPrivacyPolicy.sanitized([
            "diagnostic_reason": "Error at /private/user/memory.m4a",
            "action": "Tapped on a private story title"
        ]).isEmpty)
    }

    @Test func rejectsRemovedOnboardingSampleAction() {
        #expect(AnalyticsPrivacyPolicy.sanitized(["action": "sample_answer"]).isEmpty)
    }

    @Test func rejectsNegativeMetrics() {
        #expect(AnalyticsPrivacyPolicy.sanitized([
            "duration_ms": -1, "characters_saved": -2, "recording_duration": -0.5
        ]).isEmpty)
    }
    @Test func permitsAuditedFunnelMetadataAndRejectsArbitraryLabels() {
        let properties: Properties = [
            "screen": "reveal", "action": "continue", "field": "story",
            "flow_id": UUID().uuidString, "presentation_id": UUID().uuidString,
            "onboarding_version": "native_v5", "purchase_origin": "restore",
            "failure_stage": "activation", "dismissal_reason": "close_button",
            "generation_attempt": 1, "step_duration_ms": 500,
            "provider": "apple", "auth_operation": "link_account"
        ]
        #expect(AnalyticsPrivacyPolicy.sanitized(properties).count == properties.count)
        #expect(AnalyticsPrivacyPolicy.sanitized([
            "screen": "private story", "action": "private name", "field": "password",
            "flow_id": "private identifier", "presentation_id": "private identifier",
            "provider": "private email", "failure_stage": "private error"
        ]).isEmpty)
    }
}
