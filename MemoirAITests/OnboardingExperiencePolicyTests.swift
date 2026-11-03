import XCTest
@testable import MemoirAI

final class OnboardingExperiencePolicyTests: XCTestCase {
    private let usableStory = "We spent every summer afternoon beside the lake."

    func testReadinessPrioritizesRecordingThenFinalizationThenSpeaker() {
        XCTAssertEqual(OnboardingInputReadiness.evaluate(story: "", isRecording: true, isFinalizing: true,
                                                       audience: .parentOrGrandparent, storyteller: nil), .recording)
        XCTAssertEqual(OnboardingInputReadiness.evaluate(story: "", isRecording: false, isFinalizing: true,
                                                       audience: .parentOrGrandparent, storyteller: nil), .finalizing)
        for audience in [OnboardingAudience.parentOrGrandparent, .someoneElse] {
            XCTAssertEqual(OnboardingInputReadiness.evaluate(story: usableStory, isRecording: false, isFinalizing: false,
                                                           audience: audience, storyteller: nil), .needsStoryteller)
            for speaker in OnboardingStoryteller.allCases {
                XCTAssertEqual(OnboardingInputReadiness.evaluate(story: usableStory, isRecording: false, isFinalizing: false,
                                                               audience: audience, storyteller: speaker), .ready)
            }
        }
    }

    func testPersonalMemoirsDoNotRequireSpeakerSelection() {
        for audience in [OnboardingAudience.myself, .myChildren, .notSure] {
            XCTAssertEqual(OnboardingInputReadiness.evaluate(story: usableStory, isRecording: false, isFinalizing: false,
                                                           audience: audience, storyteller: nil), .ready)
        }
    }

    func testReadinessUsesExistingStoryValidationBoundaries() {
        let cases: [(String, OnboardingInputReadiness)] = [
            (" \n\t", .empty),
            ("One two three four five", .tooShort),
            ("One two three four five six", .ready),
            ("One two three four five " + String(repeating: "x", count: 11_976), .ready),
            ("One two three four five " + String(repeating: "x", count: 11_977), .tooLong),
            (String(repeating: "😀", count: 6_001), .tooLong)
        ]
        for (text, expected) in cases {
            XCTAssertEqual(OnboardingInputReadiness.evaluate(story: text, isRecording: false, isFinalizing: false,
                                                           audience: .myself, storyteller: nil), expected)
        }
    }

    func testResumeStartsUntouchedSessionAtAudience() {
        XCTAssertEqual(OnboardingResumePolicy.destination(for: OnboardingSession()), .audience)
    }

    func testMatchingProfilePreservesEntireSessionIncludingGenerationIdentifiers() {
        var saved = OnboardingSession()
        saved.audience = .parentOrGrandparent
        saved.narratorName = "Alex"
        saved.storyteller = .helper
        saved.stage = 9
        XCTAssertEqual(OnboardingResumePolicy.scopedSession(saved, profileID: saved.profileID), saved)
    }

    func testDifferentProfileResetsInputsAndGenerationIdentifiers() {
        var saved = OnboardingSession()
        saved.audience = .parentOrGrandparent
        saved.narratorName = "Alex"
        saved.storyteller = .helper
        saved.stage = 9
        let selectedProfile = UUID()
        let scoped = OnboardingResumePolicy.scopedSession(saved, profileID: selectedProfile)
        XCTAssertEqual(scoped.profileID, selectedProfile)
        XCTAssertNil(scoped.audience)
        XCTAssertEqual(scoped.narratorName, "")
        XCTAssertNil(scoped.storyteller)
        XCTAssertEqual(scoped.stage, 0)
        XCTAssertNotEqual(scoped.memoryID, saved.memoryID)
        XCTAssertNotEqual(scoped.requestID, saved.requestID)
        XCTAssertEqual(OnboardingResumePolicy.destination(for: scoped), .audience)
    }

    func testResumeRequiresAudienceEvenWithStoredNameAndLateStage() {
        var session = OnboardingSession()
        session.narratorName = "Alex"
        session.stage = 10
        XCTAssertEqual(OnboardingResumePolicy.destination(for: session), .audience)
    }

    func testResumePreservesExplorationWhenNameIsMissing() {
        for audience in OnboardingAudience.allCases {
            var session = OnboardingSession()
            session.audience = audience
            for name in ["", " \n", String(repeating: "a", count: 101)] {
                session.narratorName = name
                XCTAssertEqual(OnboardingResumePolicy.destination(for: session), audience == .notSure ? .meetAlex : .name)
            }
        }
    }

    func testResumeValidIdentityReturnsToInputAtEveryStoredStage() {
        for audience in OnboardingAudience.allCases {
            var session = OnboardingSession()
            session.audience = audience
            for name in [" A ", String(repeating: "a", count: 100)] {
                session.narratorName = name
                for stage in [-1, 0, 1, 2, 3, 9, 10, 999] {
                    session.stage = stage
                    XCTAssertEqual(OnboardingResumePolicy.destination(for: session), .record)
                }
            }
        }
    }
}
