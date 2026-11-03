import XCTest
@testable import MemoirAI

final class StoryEditingDraftStoreTests: XCTestCase {
    private var directory: URL!
    private let profileID = UUID()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testDraftSurvivesStoreRecreationWithTextAndAudioMetadata() throws {
        let audio = directory.appendingPathComponent("recording.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let draft = StoryEditingDraft(text: "The garden", prompt: "A childhood place", audioURL: audio,
                                      rawTranscript: "The garden", narratorName: "June", audience: .myself,
                                      storyteller: .subject, interviewMode: true, interviewAudioProcessed: true)
        try StoryEditingDraftStore(directory: directory).save(draft, userID: "owner", profileID: profileID, flow: .recording)
        let restored = try StoryEditingDraftStore(directory: directory).load(userID: "owner", profileID: profileID, flow: .recording)
        XCTAssertEqual(restored, draft)
        XCTAssertEqual(try Data(contentsOf: audio), Data([1, 2, 3]))
    }

    func testChapterPromptsAndChildVariantsRemainSeparateAfterRelaunch() throws {
        let store = StoryEditingDraftStore(directory: directory)
        let first = "parent\u{0}Childhood\u{0}A day with Sophie"
        let second = "parent\u{0}Childhood\u{0}A day with Alex"
        try store.save(StoryEditingDraft(text: "Sophie's story"), userID: "owner", profileID: profileID, flow: .chapterRecording, contextID: first)
        try store.save(StoryEditingDraft(text: "Alex's story"), userID: "owner", profileID: profileID, flow: .chapterRecording, contextID: second)
        let restored = StoryEditingDraftStore(directory: directory)
        XCTAssertEqual(try restored.load(userID: "owner", profileID: profileID, flow: .chapterRecording, contextID: first)?.text, "Sophie's story")
        XCTAssertEqual(try restored.load(userID: "owner", profileID: profileID, flow: .chapterRecording, contextID: second)?.text, "Alex's story")
        try restored.clear(userID: "owner", profileID: profileID, flow: .chapterRecording, contextID: first)
        XCTAssertNotNil(try restored.load(userID: "owner", profileID: profileID, flow: .chapterRecording, contextID: second))
    }

    func testAccountCleanupRemovesOnlyThatAccountsMetadataAcrossProfilesAndFlows() throws {
        let store = StoryEditingDraftStore(directory: directory)
        let anotherProfile = UUID()
        XCTAssertFalse(try store.hasDraft(userID: "owner", profileID: profileID))
        try store.save(StoryEditingDraft(text: "Private"), userID: "owner", profileID: profileID, flow: .recording)
        try store.save(StoryEditingDraft(text: "Other profile"), userID: "owner", profileID: anotherProfile, flow: .chapterRecording, contextID: "question")
        try store.save(StoryEditingDraft(text: "Other owner"), userID: "other", profileID: profileID, flow: .recording)
        XCTAssertTrue(try store.hasDraft(userID: "owner", profileID: profileID))
        XCTAssertTrue(try store.hasDraft(userID: "owner", profileID: anotherProfile))
        try store.clearAccount(userID: "owner")
        XCTAssertFalse(try store.hasDraft(userID: "owner", profileID: profileID))
        XCTAssertFalse(try store.hasDraft(userID: "owner", profileID: anotherProfile))
        XCTAssertTrue(try store.hasDraft(userID: "other", profileID: profileID))
    }

    func testAccountAudioCleanupOnlyIncludesExclusiveAppRecordings() throws {
        let store = StoryEditingDraftStore(directory: directory.appendingPathComponent("drafts"))
        let recordings = directory.appendingPathComponent("recordings")
        let own = recordings.appendingPathComponent(UUID().uuidString + ".m4a")
        let shared = recordings.appendingPathComponent(UUID().uuidString + ".m4a")
        let submitted = recordings.appendingPathComponent(UUID().uuidString + ".m4a")
        let external = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        let arbitrary = recordings.appendingPathComponent("original.m4a")
        for (index, audio) in [own, shared, submitted, external, arbitrary].enumerated() {
            try store.save(StoryEditingDraft(text: "", audioURL: audio), userID: "owner", profileID: profileID,
                           flow: .chapterRecording, contextID: String(index))
        }
        try store.save(StoryEditingDraft(text: "", audioURL: shared), userID: "other", profileID: profileID, flow: .recording)
        XCTAssertEqual(try store.exclusiveRecordingURLs(userID: "owner", recordingsDirectory: recordings,
                                                      preserving: [submitted]), [own])
        XCTAssertTrue(try store.exclusiveRecordingURLs(userID: "absent", recordingsDirectory: recordings,
                                                       preserving: []).isEmpty)
    }

    func testAccountProfileAndFlowAreIsolated() throws {
        let store = StoryEditingDraftStore(directory: directory)
        try store.save(StoryEditingDraft(text: "Private story"), userID: "owner", profileID: profileID, flow: .recording)
        XCTAssertNil(try store.load(userID: "other", profileID: profileID, flow: .recording))
        XCTAssertNil(try store.load(userID: "owner", profileID: UUID(), flow: .recording))
        XCTAssertNil(try store.load(userID: "owner", profileID: profileID, flow: .onboarding))
    }

    func testCorruptForeignDraftPreservesAudioWithoutBlockingOwnedMetadataCleanup() throws {
        let drafts = directory.appendingPathComponent("drafts")
        let store = StoryEditingDraftStore(directory: drafts)
        let audio = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data([1, 2, 3]).write(to: audio)
        try store.save(StoryEditingDraft(text: "Other account", audioURL: audio),
                       userID: "other", profileID: profileID, flow: .onboarding)
        let foreignFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: drafts, includingPropertiesForKeys: nil).first)
        let malformed = Data("incomplete".utf8)
        try malformed.write(to: foreignFile)
        try store.save(StoryEditingDraft(text: "Owned story", audioURL: audio),
                       userID: "owner", profileID: profileID, flow: .onboarding)

        XCTAssertTrue(try store.exclusiveRecordingURLs(userID: "owner", recordingsDirectory: directory,
                                                       preserving: []).isEmpty)
        try store.clearAccount(userID: "owner")
        XCTAssertNil(try store.load(userID: "owner", profileID: profileID, flow: .onboarding))
        XCTAssertEqual(try Data(contentsOf: foreignFile), malformed)
        XCTAssertEqual(try Data(contentsOf: audio), Data([1, 2, 3]))
    }

    func testDiscardRemovesOnlyScopedMetadataNeverAudio() throws {
        let store = StoryEditingDraftStore(directory: directory)
        let audio = directory.appendingPathComponent("shared.m4a")
        try Data([7]).write(to: audio)
        try store.save(StoryEditingDraft(text: "", audioURL: audio), userID: "owner", profileID: profileID, flow: .recording)
        try store.save(StoryEditingDraft(text: "First story"), userID: "owner", profileID: profileID, flow: .onboarding)
        try store.clear(userID: "owner", profileID: profileID, flow: .recording)
        try store.clear(userID: "owner", profileID: profileID, flow: .recording)
        XCTAssertNil(try store.load(userID: "owner", profileID: profileID, flow: .recording))
        XCTAssertNotNil(try store.load(userID: "owner", profileID: profileID, flow: .onboarding))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testEditingDraftNeverCarriesGenerationIdentifiersOrOverwritesSubmittedSnapshot() throws {
        let submitted = OnboardingDraftStore(directory: directory.appendingPathComponent("submitted"))
        let session = OnboardingSession()
        let original = OnboardingDraft(session: session, story: "Original", rawTranscript: nil, audioURL: nil, photoData: nil)
        try submitted.save(original, userID: "owner")
        let editing = StoryEditingDraftStore(directory: directory.appendingPathComponent("editing"))
        let changed = StoryEditingDraft(text: "Changed", narratorName: "June", audience: .myself)
        try editing.save(changed, userID: "owner", profileID: profileID, flow: .onboarding)
        let recoveredSubmitted = try XCTUnwrap(submitted.load(userID: "owner"))
        XCTAssertEqual(recoveredSubmitted.story, "Original")
        XCTAssertEqual(recoveredSubmitted.session.memoryID, session.memoryID)
        XCTAssertEqual(recoveredSubmitted.session.requestID, session.requestID)
        XCTAssertNotEqual(recoveredSubmitted.story, try editing.load(userID: "owner", profileID: profileID, flow: .onboarding)?.text)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(changed)) as? [String: Any])
        XCTAssertNil(encoded["memoryID"])
        XCTAssertNil(encoded["requestID"])
        XCTAssertNil(encoded["session"])
    }

    func testMissingAudioMetadataIsRetainedForRecovery() throws {
        let store = StoryEditingDraftStore(directory: directory)
        let missing = directory.appendingPathComponent("missing.m4a")
        try store.save(StoryEditingDraft(text: "Preserved words", audioURL: missing), userID: "owner", profileID: profileID, flow: .recording)
        XCTAssertEqual(try store.load(userID: "owner", profileID: profileID, flow: .recording)?.audioURL, missing)
    }

    func testContentRequiresWordsOrRecordingRatherThanPromptAlone() {
        XCTAssertFalse(StoryEditingDraft(text: " \n", prompt: "A question").hasContent)
        XCTAssertTrue(StoryEditingDraft(text: "A story").hasContent)
        XCTAssertTrue(StoryEditingDraft(text: "", audioURL: directory.appendingPathComponent("audio.m4a")).hasContent)
    }

    func testCorruptedDraftReportsFailureInsteadOfOverwritingIt() throws {
        let store = StoryEditingDraftStore(directory: directory)
        try store.save(StoryEditingDraft(text: "Original"), userID: "owner", profileID: profileID, flow: .recording)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let corrupt = Data("incomplete".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try store.load(userID: "owner", profileID: profileID, flow: .recording))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
}
