import XCTest
@testable import MemoirAI

final class OnboardingDraftStoreTests: XCTestCase {
    func testDraftRoundTripIsOwnerScopedAndClearIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OnboardingDraftStore(directory: root)
        var session = OnboardingSession()
        session.audience = .parentOrGrandparent
        session.storyteller = .helper
        let draft = OnboardingDraft(session: session, story: "We played beside the river.", rawTranscript: "Um we played beside the river.", audioURL: URL(fileURLWithPath: "/test.m4a"), photoData: Data([1, 2, 3]))
        try store.save(draft, userID: "owner/a")
        let loaded = try XCTUnwrap(store.load(userID: "owner/a"))
        XCTAssertEqual(loaded.session, session)
        XCTAssertEqual(loaded.rawTranscript, draft.rawTranscript)
        XCTAssertEqual(loaded.photoData, draft.photoData)
        XCTAssertEqual(loaded.audioURL, draft.audioURL)
        XCTAssertNil(try store.load(userID: "other"))
        try store.clear(userID: "owner/a")
        try store.clear(userID: "owner/a")
        XCTAssertNil(try store.load(userID: "owner/a"))
    }
}
