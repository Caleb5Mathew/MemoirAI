import Mixpanel

enum AnalyticsPrivacyPolicy {
    private static let disallowedPropertyKeys: Set<String> = [
        "memory_id",
        "prompt_text"
    ]

    static func sanitized(_ properties: Properties) -> Properties {
        properties.filter { !disallowedPropertyKeys.contains($0.key) }
    }
}
