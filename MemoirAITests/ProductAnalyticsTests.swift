import Foundation
import Mixpanel
import Testing
@testable import MemoirAI

@MainActor
struct ProductAnalyticsTests {
    @Test func marksTestHostTrafficSeparately() {
        #expect(ProductAnalytics.buildEnvironment == "test")
    }

    @Test func protectsContentAndAddsTrustedContext() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var received: Properties = [:]
        let analytics = ProductAnalytics(send: { _, props in received = props }, identify: { _ in }, reset: {}, defaults: defaults, environment: "test")
        analytics.track("Test", ["transcript": "private", "environment": "spoofed", "has_audio": true])
        #expect(received["transcript"] == nil)
        #expect(received["environment"] as? String == "test")
        #expect(received["has_audio"] as? Bool == true)
        #expect(received["session_id"] as? String != nil)
    }

    @Test func preservesGuestUpgradeAndResetsOnAccountChange() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var resets = 0
        var identities: [String] = []
        let analytics = ProductAnalytics(send: { _, _ in }, identify: { identities.append($0) }, reset: { resets += 1 }, defaults: defaults)
        analytics.updateIdentity(userID: "guest", isGuest: true)
        analytics.updateIdentity(userID: "guest", isGuest: false)
        #expect(resets == 0)
        analytics.updateIdentity(userID: "other", isGuest: false)
        #expect(resets == 1)
        analytics.updateIdentity(userID: nil, isGuest: true)
        analytics.updateIdentity(userID: nil, isGuest: true)
        #expect(resets == 2)
        #expect(identities == ["guest", "guest", "other"])
    }

    @Test func deduplicatesSessionsAndMeasuresActiveDuration() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var events: [(String, Properties)] = []
        var date = Date(timeIntervalSince1970: 0)
        let analytics = ProductAnalytics(send: { events.append(($0, $1)) }, identify: { _ in }, reset: {}, defaults: defaults, now: { date })
        analytics.setSessionActive(true)
        analytics.setSessionActive(true)
        date = date.addingTimeInterval(2)
        analytics.setSessionActive(false)
        analytics.setSessionActive(false)
        #expect(events.map(\.0) == ["Session Started", "Session Ended"])
        #expect(events.last?.1["duration_ms"] as? Int == 2000)
    }

    @Test func aggregatesInputAndAuditsScreenActions() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var events: [(String, Properties)] = []
        let analytics = ProductAnalytics(send: { events.append(($0, $1)) }, identify: { _ in }, reset: {}, defaults: defaults)
        analytics.screen("record")
        analytics.action("continue", screen: "record")
        analytics.inputStarted(field: "story", screen: "record")
        analytics.inputStarted(field: "story", screen: "record")
        analytics.inputCompleted(field: "story", screen: "record", characterCount: 42)
        analytics.inputCompleted(field: "story", screen: "record", characterCount: 42)
        #expect(events.map(\.0) == ["Screen Viewed", "UI Action", "Input Started", "Input Completed"])
        #expect(events.last?.1["character_count"] as? Int == 42)
    }
}

@MainActor
struct AnalyticsTrafficContextTests {
    @Test func separatesHardwareFromTrafficClassification() {
        let physical = AnalyticsTrafficContext(isSimulator: false, explicitlyInternal: false, internalUserIDs: ["qa"])
        #expect(physical.properties(environment: "production", userID: "reader")["traffic_type"] as? String == "external")
        #expect(physical.properties(environment: "production", userID: "qa")["traffic_type"] as? String == "internal")
        for environment in ["development", "test", "sandbox"] {
            #expect(physical.properties(environment: environment, userID: "reader")["traffic_type"] as? String == "internal")
        }
        let simulator = AnalyticsTrafficContext(isSimulator: true, explicitlyInternal: false, internalUserIDs: [])
        #expect(simulator.properties(environment: "production", userID: nil)["traffic_type"] as? String == "internal")
        #expect(simulator.properties(environment: "production", userID: nil)["is_simulator"] as? Bool == true)
        #expect(physical.properties(environment: "production", userID: nil)["device_type"] as? String == "physical")
        let explicitQA = AnalyticsTrafficContext(isSimulator: false, explicitlyInternal: true, internalUserIDs: [])
        #expect(explicitQA.properties(environment: "production", userID: "reader")["traffic_type"] as? String == "internal")
    }

    @Test func trustedTrafficCannotBeSpoofedAndResetsWithIdentity() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var received: Properties = [:]
        var registered: Properties = [:]
        let analytics = ProductAnalytics(
            send: { _, props in received = props }, identify: { _ in }, reset: {},
            defaults: defaults, environment: "production",
            trafficContext: .init(isSimulator: false, explicitlyInternal: false, internalUserIDs: ["qa"]),
            registerContext: { registered = $0 }
        )
        analytics.updateIdentity(userID: "qa", isGuest: false)
        analytics.track("Example", ["traffic_type": "external", "is_simulator": true])
        #expect(received["traffic_type"] as? String == "internal")
        #expect(received["is_simulator"] as? Bool == false)
        #expect(registered["traffic_type"] as? String == "internal")
        analytics.updateIdentity(userID: "reader", isGuest: false)
        #expect(registered["traffic_type"] as? String == "external")
        #expect(registered["environment"] as? String == "production")
    }
}
