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

    @Test func assignsTrustedEventCategoryWithoutRenamingEvents() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var events: [(String, Properties)] = []
        let analytics = ProductAnalytics(send: { events.append(($0, $1)) }, identify: { _ in }, reset: {}, defaults: defaults)
        analytics.track("Onboarding Preview Image Ready", ["event_category": "Subscriptions"])
        analytics.track("Subscription Activation Succeeded")
        analytics.track("Future Event", ["event_category": "Subscriptions"])
        #expect(events.map(\.0) == ["Onboarding Preview Image Ready", "Subscription Activation Succeeded", "Future Event"])
        #expect(events[0].1["event_category"] as? String == "Onboarding generation")
        #expect(events[1].1["event_category"] as? String == "Subscriptions")
        #expect(events[2].1["event_category"] as? String == "Uncategorized")
    }

    @Test func distinguishesProductStagesInEventCategories() {
        #expect(AnalyticsEventCategory.category(for: "Onboarding Sample Playback Started") == "Onboarding sample tour")
        #expect(AnalyticsEventCategory.category(for: "Memory Playback Completed") == "Memory reading and listening")
        #expect(AnalyticsEventCategory.category(for: "Book Generation Completed") == "Book creation")
        #expect(AnalyticsEventCategory.category(for: "Saved Memory") == "Memory creation")
        #expect(AnalyticsEventCategory.category(for: "Unknown Event") == "Uncategorized")
        #expect(AnalyticsEventCategory.categories.values.allSatisfy { !$0.isEmpty })
    }

    @Test func screenDwellPausesWhileInactiveAndResumesWithoutAnotherView() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var date = Date(timeIntervalSince1970: 0)
        var events: [(String, Properties)] = []
        let analytics = ProductAnalytics(send: { events.append(($0, $1)) }, identify: { _ in }, reset: {}, defaults: defaults, now: { date })
        let screenID = UUID()
        analytics.beginScreen("home", id: screenID)
        date = date.addingTimeInterval(10)
        analytics.setScreenTrackingActive(true)
        date = date.addingTimeInterval(2)
        analytics.setScreenTrackingActive(false)
        analytics.setScreenTrackingActive(false)
        date = date.addingTimeInterval(100)
        analytics.setScreenTrackingActive(true)
        date = date.addingTimeInterval(3)
        analytics.endScreen(id: screenID)
        analytics.endScreen(id: screenID)
        let dwell = events.filter { $0.0 == "Screen Time Recorded" }
        #expect(dwell.map { $0.1["duration_ms"] as? Int } == [2000, 3000])
        #expect(dwell.map { $0.1["screen_exit_reason"] as? String } == ["inactive", "navigation"])
        #expect(events.filter { $0.0 == "Screen Viewed" }.count == 1)
    }

    @Test func nestedScreenDwellRestoresUnderlyingScreenAndIgnoresStaleDisappear() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var date = Date(timeIntervalSince1970: 0)
        var events: [(String, Properties)] = []
        let analytics = ProductAnalytics(send: { events.append(($0, $1)) }, identify: { _ in }, reset: {}, defaults: defaults, now: { date })
        let home = UUID(), detail = UUID(), paywall = UUID()
        analytics.setScreenTrackingActive(true)
        analytics.beginScreen("home", id: home)
        analytics.beginScreen("home", id: home)
        date = date.addingTimeInterval(1)
        analytics.beginScreen("memory_detail", id: detail)
        date = date.addingTimeInterval(2)
        analytics.beginScreen("paywall", id: paywall)
        analytics.endScreen(id: detail)
        date = date.addingTimeInterval(3)
        analytics.endScreen(id: paywall)
        date = date.addingTimeInterval(4)
        analytics.endScreen(id: home)
        let dwell = events.filter { $0.0 == "Screen Time Recorded" }
        #expect(dwell.map { $0.1["screen"] as? String } == ["home", "memory_detail", "paywall", "home"])
        #expect(dwell.map { $0.1["duration_ms"] as? Int } == [1000, 2000, 3000, 4000])
        #expect(events.filter { $0.0 == "Screen Viewed" }.count == 3)
    }

    @Test func dynamicScreensRejectPrivateNamesAndSeparateIdentityDurations() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var date = Date(timeIntervalSince1970: 0)
        var events: [(String, Properties)] = []
        let analytics = ProductAnalytics(send: { events.append(($0, $1)) }, identify: { _ in }, reset: {}, defaults: defaults, now: { date })
        let screenID = UUID()
        analytics.setScreenTrackingActive(true)
        analytics.beginScreen("private memoir title", id: UUID())
        #expect(events.isEmpty)
        analytics.beginScreen("audience", id: screenID)
        date = date.addingTimeInterval(1)
        analytics.beginScreen("name", id: screenID)
        date = date.addingTimeInterval(2)
        analytics.updateIdentity(userID: "reader", isGuest: false)
        date = date.addingTimeInterval(3)
        analytics.endScreen(id: screenID)
        let dwell = events.filter { $0.0 == "Screen Time Recorded" }
        #expect(dwell.map { $0.1["duration_ms"] as? Int } == [1000, 2000, 3000])
        #expect(dwell.map { $0.1["account_type"] as? String } == ["unidentified", "unidentified", "registered"])
        #expect(dwell[1].1["screen_exit_reason"] as? String == "identity_changed")
    }

    @Test func backwardClockDoesNotProduceNegativeScreenTime() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var date = Date(timeIntervalSince1970: 10)
        var events: [String] = []
        let analytics = ProductAnalytics(send: { name, _ in events.append(name) }, identify: { _ in }, reset: {}, defaults: defaults, now: { date })
        analytics.setScreenTrackingActive(true)
        let screenID = UUID()
        analytics.beginScreen("home", id: screenID)
        date = date.addingTimeInterval(-5)
        analytics.endScreen(id: screenID)
        #expect(events == ["Screen Viewed"])
    }

    @Test func enhancementDraftSurvivesFailedSaveUntilSuccessfulRetry() throws {
        enum SaveError: Error { case storageUnavailable }
        let memoryID = UUID()
        defer { EnhancementSessionDraft.clear(memoryId: memoryID) }
        let draft = EnhancementSessionDraft(
            turns: [MemoryEnhancementTurn(question: "Who was there?", answer: "My sister")],
            currentQuestion: "What happened next?", promptContext: nil
        )
        draft.save(memoryId: memoryID)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let analytics = ProductAnalytics(send: { _, _ in }, identify: { _ in }, reset: {}, defaults: defaults)
        let failed = MemoryEnhancementSaveOperation.perform(characterCount: 1, memoryID: memoryID, analytics: analytics) {
            throw SaveError.storageUnavailable
        }
        #expect(!failed)
        #expect(EnhancementSessionDraft.load(memoryId: memoryID) == draft)
        let saved = MemoryEnhancementSaveOperation.perform(characterCount: 1, memoryID: memoryID, analytics: analytics) {
            #expect(EnhancementSessionDraft.load(memoryId: memoryID) == draft)
        }
        #expect(saved)
        #expect(EnhancementSessionDraft.load(memoryId: memoryID) == nil)
    }

    @Test func enhancementSaveFailureDoesNotReportSuccessAndCanRetry() throws {
        enum SaveError: Error { case storageUnavailable }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        var events: [(String, Properties)] = []
        var persisted = false
        let analytics = ProductAnalytics(send: { events.append(($0, $1)) }, identify: { _ in }, reset: {}, defaults: defaults)
        let failed = MemoryEnhancementSaveOperation.perform(characterCount: 2, analytics: analytics) {
            throw SaveError.storageUnavailable
        }
        #expect(!failed)
        #expect(events.map(\.0) == ["Memory Enhancement Save Failed"])
        #expect(events[0].1["failure_stage"] as? String == "local_save")
        #expect(events[0].1["characters_saved"] == nil)
        let retried = MemoryEnhancementSaveOperation.perform(characterCount: 2, analytics: analytics) {
            persisted = true
            #expect(events.map(\.0) == ["Memory Enhancement Save Failed"])
        }
        #expect(retried && persisted)
        #expect(events.map(\.0) == ["Memory Enhancement Save Failed", "Memory Enhancement Auto Saved"])
        #expect(events[1].1["characters_saved"] as? Int == 2)
        #expect(events[1].1["event_category"] as? String == "Memory enhancement")
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
