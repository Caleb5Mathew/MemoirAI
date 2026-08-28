import Foundation
import Testing
@testable import MemoirAI

struct MemorySharePreparationTests {
    @Test func remoteHTTPSAudioRequiresDownloadBeforeSharing() {
        let remoteURL = URL(string: "https://example.com/audio/memory.m4a")!

        let request = MemorySharePreparationPolicy.request(
            text: "  A memory to share.  ",
            localAudioURL: nil,
            storedAudioURL: remoteURL.absoluteString
        )

        #expect(request.text == "A memory to share.")
        #expect(request.localAudioURL == nil)
        #expect(request.remoteAudioURL == remoteURL)
        #expect(request.hasContent)
    }

    @Test func emptyTextAndUnsafeRemoteURLNeverCreateShareContent() {
        let request = MemorySharePreparationPolicy.request(
            text: " \n ",
            localAudioURL: nil,
            storedAudioURL: "http://example.com/audio.m4a"
        )

        #expect(!request.hasContent)
    }

    @Test func completedDownloadCannotCrossAccountsOrMemoryRevisions() throws {
        let memoryID = UUID()
        let expected = try #require(MemorySharePreparationPolicy.context(
            memoryID: memoryID,
            ownerID: "user-a",
            textReference: "A saved memory",
            audioReference: "https://example.com/first.m4a"
        ))

        #expect(MemorySharePreparationPolicy.isCurrent(
            expected: expected,
            memoryID: memoryID,
            ownerID: "user-a",
            textReference: "A saved memory",
            audioReference: "https://example.com/first.m4a",
            currentUserID: "user-a"
        ))
        #expect(!MemorySharePreparationPolicy.isCurrent(
            expected: expected,
            memoryID: memoryID,
            ownerID: "user-a",
            textReference: "A saved memory",
            audioReference: "https://example.com/first.m4a",
            currentUserID: "user-b"
        ))
        #expect(!MemorySharePreparationPolicy.isCurrent(
            expected: expected,
            memoryID: memoryID,
            ownerID: "user-a",
            textReference: "A saved memory",
            audioReference: "https://example.com/replaced.m4a",
            currentUserID: "user-a"
        ))
        #expect(!MemorySharePreparationPolicy.isCurrent(
            expected: expected,
            memoryID: memoryID,
            ownerID: "user-a",
            textReference: "A different memory text",
            audioReference: "https://example.com/first.m4a",
            currentUserID: "user-a"
        ))
    }
}
