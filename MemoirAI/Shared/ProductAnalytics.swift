import Foundation
import Mixpanel

/// Product telemetry contains audited interaction metadata only, never memoir content.
@MainActor
final class ProductAnalytics {
    static let shared = ProductAnalytics(
        send: { Mixpanel.mainInstance().track(event: $0, properties: $1) },
        identify: { Mixpanel.mainInstance().identify(distinctId: $0) },
        reset: {
            Mixpanel.mainInstance().reset()
            Mixpanel.mainInstance().registerSuperProperties([
                "environment": ProductAnalytics.buildEnvironment, "schema_version": 1
            ])
        }
    )

    private let send: (String, Properties) -> Void
    private let identify: (String) -> Void
    private let reset: () -> Void
    private let now: () -> Date
    private let defaults: UserDefaults
    private let environment: String
    private var userID: String?
    private var isGuest = true
    private var sessionID = UUID().uuidString
    private var activeSince: Date?
    private var inputs: [String: Date] = [:]
    private static let identityKey = "memoirai.analytics.identity"

    init(
        send: @escaping (String, Properties) -> Void,
        identify: @escaping (String) -> Void,
        reset: @escaping () -> Void,
        defaults: UserDefaults = .standard,
        environment: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.send = send
        self.identify = identify
        self.reset = reset
        self.defaults = defaults
        self.environment = environment ?? Self.buildEnvironment
        self.now = now
        userID = defaults.string(forKey: Self.identityKey)
    }

    static var buildEnvironment: String {
        if NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "test"
        }
        #if DEBUG
        return "development"
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "sandbox" : "production"
        #endif
    }

    static func configure() {
        let configuredToken = Bundle.main.object(forInfoDictionaryKey: "MixpanelToken") as? String
        let token = configuredToken.flatMap { $0.isEmpty ? nil : $0 }
            ?? "ca3f4918c79c2dee9957d0b18a1e0027"
        Mixpanel.initialize(token: token, trackAutomaticEvents: false)
        Mixpanel.mainInstance().useIPAddressForGeoLocation = false
        Mixpanel.mainInstance().registerSuperProperties([
            "environment": buildEnvironment, "schema_version": 1
        ])
    }

    func track(_ event: String, _ properties: Properties = [:]) {
        var safe = AnalyticsPrivacyPolicy.sanitized(properties)
        safe["environment"] = environment
        safe["schema_version"] = 1
        safe["session_id"] = sessionID
        safe["account_type"] = userID == nil ? "unidentified" : (isGuest ? "guest" : "registered")
        send(event, safe)
    }

    func updateIdentity(userID nextID: String?, isGuest: Bool) {
        if userID != nextID {
            if userID != nil {
                reset()
                sessionID = UUID().uuidString
            }
            inputs.removeAll()
            userID = nextID
            if let nextID { defaults.set(nextID, forKey: Self.identityKey) }
            else { defaults.removeObject(forKey: Self.identityKey) }
        }
        self.isGuest = isGuest
        if let nextID { identify(nextID) }
    }

    func setSessionActive(_ active: Bool) {
        if active {
            guard activeSince == nil else { return }
            sessionID = UUID().uuidString
            activeSince = now()
            track("Session Started")
        } else {
            guard let started = activeSince else { return }
            track("Session Ended", ["duration_ms": max(0, Int(now().timeIntervalSince(started) * 1000))])
            activeSince = nil
            inputs.removeAll()
        }
    }

    func screen(_ screen: String) {
        track("Screen Viewed", ["screen": screen])
    }

    func action(_ action: String, screen: String) {
        track("UI Action", ["action": action, "screen": screen])
    }

    func inputStarted(field: String, screen: String) {
        let key = screen + ":" + field
        guard inputs[key] == nil else { return }
        inputs[key] = now()
        track("Input Started", ["field": field, "screen": screen])
    }

    func inputCompleted(field: String, screen: String, characterCount: Int) {
        guard let started = inputs.removeValue(forKey: screen + ":" + field) else { return }
        track("Input Completed", [
            "field": field, "screen": screen,
            "character_count": max(0, characterCount),
            "duration_ms": max(0, Int(now().timeIntervalSince(started) * 1000))
        ])
    }
}
