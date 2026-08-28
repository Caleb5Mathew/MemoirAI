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
}
