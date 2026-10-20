import Foundation
import SwiftUI
import Mixpanel

struct AnalyticsTrafficContext {
    let isSimulator: Bool
    let explicitlyInternal: Bool
    let internalUserIDs: Set<String>

    static var runtime: Self {
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        // An explicit QA launch persists across app updates on this installation.
        if ProcessInfo.processInfo.arguments.contains("-analytics-internal") {
            UserDefaults.standard.set(true, forKey: "memoirai.analytics.internalInstallation")
        }
        return Self(
            isSimulator: simulator,
            explicitlyInternal: UserDefaults.standard.bool(forKey: "memoirai.analytics.internalInstallation"),
            internalUserIDs: Set(Bundle.main.object(forInfoDictionaryKey: "AnalyticsInternalUserIDs") as? [String] ?? [])
        )
    }

    func properties(environment: String, userID: String?) -> Properties {
        let internalTraffic = isSimulator || environment != "production" || explicitlyInternal
            || userID.map(internalUserIDs.contains) == true
        return [
            "device_type": isSimulator ? "simulator" : "physical",
            "is_simulator": isSimulator,
            "traffic_type": internalTraffic ? "internal" : "external"
        ]
    }
}

/// Product telemetry contains audited interaction metadata only, never memoir content.
@MainActor
final class ProductAnalytics {
    static let shared = ProductAnalytics(
        send: { Mixpanel.mainInstance().track(event: $0, properties: $1) },
        identify: { Mixpanel.mainInstance().identify(distinctId: $0) },
        reset: { Mixpanel.mainInstance().reset() },
        registerContext: { Mixpanel.mainInstance().registerSuperProperties($0) }
    )

    private let send: (String, Properties) -> Void
    private let identify: (String) -> Void
    private let reset: () -> Void
    private let now: () -> Date
    private let defaults: UserDefaults
    private let environment: String
    private let trafficContext: AnalyticsTrafficContext
    private let registerContext: (Properties) -> Void
    private var userID: String?
    private var isGuest = true
    private var sessionID = UUID().uuidString
    private var activeSince: Date?
    private var inputs: [String: Date] = [:]
    private var visibleScreens: [(id: UUID, name: String)] = []
    private var screenActiveSince: Date?
    private var screenTrackingActive = false
    private static let identityKey = "memoirai.analytics.identity"

    init(
        send: @escaping (String, Properties) -> Void,
        identify: @escaping (String) -> Void,
        reset: @escaping () -> Void,
        defaults: UserDefaults = .standard,
        environment: String? = nil,
        trafficContext: AnalyticsTrafficContext = .runtime,
        registerContext: @escaping (Properties) -> Void = { _ in },
        now: @escaping () -> Date = Date.init
    ) {
        self.send = send
        self.identify = identify
        self.reset = reset
        self.defaults = defaults
        self.environment = environment ?? Self.buildEnvironment
        self.trafficContext = trafficContext
        self.registerContext = registerContext
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
        Mixpanel.mainInstance().registerSuperProperties(shared.trustedContext)
    }

    private var trustedContext: Properties {
        var properties = trafficContext.properties(environment: environment, userID: userID)
        properties["environment"] = environment
        properties["schema_version"] = 1
        return properties
    }

    func track(_ event: String, _ properties: Properties = [:]) {
        var safe = AnalyticsPrivacyPolicy.sanitized(properties)
        safe.merge(trustedContext) { _, trusted in trusted }
        safe["event_category"] = AnalyticsEventCategory.category(for: event)
        safe["session_id"] = sessionID
        safe["account_type"] = userID == nil ? "unidentified" : (isGuest ? "guest" : "registered")
        send(event, safe)
    }

    func updateIdentity(userID nextID: String?, isGuest: Bool) {
        if userID != nextID {
            recordScreenTime(reason: "identity_changed")
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
        registerContext(trustedContext)
        if screenTrackingActive && !visibleScreens.isEmpty && screenActiveSince == nil {
            screenActiveSince = now()
        }
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

    func beginScreen(_ name: String, id: UUID) {
        guard AnalyticsPrivacyPolicy.isAllowedScreen(name) else { return }
        if let existing = visibleScreens.firstIndex(where: { $0.id == id }) {
            guard visibleScreens[existing].name != name else { return }
            if existing == visibleScreens.count - 1 {
                recordScreenTime(reason: "navigation")
            }
            visibleScreens[existing].name = name
            if existing == visibleScreens.count - 1 {
                screenActiveSince = screenTrackingActive ? now() : nil
                screen(name)
            }
            return
        }
        recordScreenTime(reason: "covered")
        visibleScreens.append((id: id, name: name))
        screenActiveSince = screenTrackingActive ? now() : nil
        screen(name)
    }

    func endScreen(id: UUID) {
        guard let index = visibleScreens.firstIndex(where: { $0.id == id }) else { return }
        let wasVisible = index == visibleScreens.count - 1
        if wasVisible { recordScreenTime(reason: "navigation") }
        visibleScreens.remove(at: index)
        if wasVisible {
            screenActiveSince = screenTrackingActive && !visibleScreens.isEmpty ? now() : nil
        }
    }

    func setScreenTrackingActive(_ active: Bool) {
        guard screenTrackingActive != active else { return }
        if !active { recordScreenTime(reason: "inactive") }
        screenTrackingActive = active
        screenActiveSince = active && !visibleScreens.isEmpty ? now() : nil
    }

    private func recordScreenTime(reason: String) {
        guard let started = screenActiveSince, let screen = visibleScreens.last?.name else { return }
        screenActiveSince = nil
        let elapsed = max(0, now().timeIntervalSince(started))
        guard elapsed > 0 else { return }
        track("Screen Time Recorded", [
            "screen": screen,
            "duration_ms": Int(min(elapsed * 1000, Double(Int.max / 2))),
            "screen_exit_reason": reason
        ])
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

/// Stable product areas for filtering events without renaming historical event streams.
enum AnalyticsEventCategory {
    static let categories: [String: String] = [
        "Authentication Failed": "Account access",
        "Authentication Started": "Account access",
        "Authentication Succeeded": "Account access",
        "Signed Out": "Account access",
        "App Launched": "App lifecycle",
        "First Launch": "App lifecycle",
        "Session Ended": "App lifecycle",
        "Session Started": "App lifecycle",
        "Book Generation Cancelled": "Book creation",
        "Book Generation Completed": "Book creation",
        "Book Generation Failed": "Book creation",
        "Book Generation Requested": "Book creation",
        "Book Illustrations Completed": "Book creation",
        "Memory Save Failed": "Memory creation",
        "Recording Start Failed": "Memory creation",
        "Memory Transcription Retry Failed": "Memory creation",
        "Memory Transcription Retry Queued": "Memory creation",
        "Opened Prompt": "Memory creation",
        "Saved Memory": "Memory creation",
        "Started Recording": "Memory creation",
        "Memory Enhancement Auto Saved": "Memory enhancement",
        "Memory Enhancement Flow Opened": "Memory enhancement",
        "Memory Enhancement Save Failed": "Memory enhancement",
        "Memory Enhancement Guided Complete": "Memory enhancement",
        "Memory Playback Completed": "Memory reading and listening",
        "Memory Playback Failed": "Memory reading and listening",
        "Memory Playback Requested": "Memory reading and listening",
        "Memory Playback Started": "Memory reading and listening",
        "Viewed Memory": "Memory reading and listening",
        "Memory Share Cancelled": "Memory sharing",
        "Memory Share Failed": "Memory sharing",
        "Memory Share Sheet Presented": "Memory sharing",
        "Memory Shared": "Memory sharing",
        "Input Completed": "Navigation and input",
        "Input Started": "Navigation and input",
        "Screen Viewed": "Navigation and input",
        "Screen Time Recorded": "Navigation and input",
        "Tab Viewed": "Navigation and input",
        "UI Action": "Navigation and input",
        "Onboarding Photo Added": "Onboarding capture",
        "Onboarding Preparation Failed": "Onboarding capture",
        "Onboarding Recording Failed": "Onboarding capture",
        "Onboarding Recording Started": "Onboarding capture",
        "Onboarding Recording Stopped": "Onboarding capture",
        "Onboarding Generation Started": "Onboarding generation",
        "Onboarding Memory Saved Locally": "Onboarding generation",
        "Onboarding Memory Synced": "Onboarding generation",
        "Onboarding Personalized Reveal Viewed": "Onboarding generation",
        "Onboarding Preview Failed": "Onboarding generation",
        "Onboarding Preview Image Ready": "Onboarding generation",
        "Onboarding Action": "Onboarding navigation",
        "Onboarding Audience Selected": "Onboarding navigation",
        "Onboarding Backgrounded": "Onboarding navigation",
        "Onboarding Completed": "Onboarding navigation",
        "Onboarding Foregrounded": "Onboarding navigation",
        "Onboarding Started": "Onboarding navigation",
        "Onboarding Step Exited": "Onboarding navigation",
        "Onboarding Step Viewed": "Onboarding navigation",
        "Onboarding Tour Finished": "Onboarding navigation",
        "Onboarding Sample Playback Started": "Onboarding sample tour",
        "Onboarding Sample Playback Stopped": "Onboarding sample tour",
        "Onboarding Paywall Viewed": "Subscriptions",
        "Paywall Dismissed": "Subscriptions",
        "Paywall Preparation Failed": "Subscriptions",
        "Paywall Viewed": "Subscriptions",
        "Subscription Activation Failed": "Subscriptions",
        "Subscription Activation Started": "Subscriptions",
        "Subscription Activation Succeeded": "Subscriptions",
        "Subscription Purchase Cancelled": "Subscriptions",
        "Subscription Purchase Failed": "Subscriptions",
        "Subscription Purchase Started": "Subscriptions",
        "Subscription Restore Failed": "Subscriptions",
        "Subscription Restore Started": "Subscriptions",
    ]

    static func category(for event: String) -> String {
        categories[event] ?? "Uncategorized"
    }
}


private struct AnalyticsScreenModifier: ViewModifier {
    let name: String
    @State private var instanceID = UUID()
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                ProductAnalytics.shared.beginScreen(name, id: instanceID)
            }
            .onChange(of: name) { _, newName in
                if isVisible { ProductAnalytics.shared.beginScreen(newName, id: instanceID) }
            }
            .onDisappear {
                isVisible = false
                ProductAnalytics.shared.endScreen(id: instanceID)
            }
    }
}

extension View {
    func analyticsScreen(_ name: String) -> some View {
        modifier(AnalyticsScreenModifier(name: name))
    }
}
