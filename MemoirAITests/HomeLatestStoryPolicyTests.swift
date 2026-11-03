import CoreData
import SwiftUI
import XCTest
@testable import MemoirAI

@MainActor
final class HomeLatestStoryPolicyTests: XCTestCase {
    private let persistence = PersistenceController(inMemory: true)
    private let profileID = UUID()

    func testLatestStoryRowRendersAtStandardAndAccessibilitySizes() throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            let row = HomeLatestStoryRow(title: "The summer we spent beside the lake with my grandparents")
                .frame(width: 354)
                .environment(\.dynamicTypeSize, size)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: row)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 354, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(image.size.height, 44)
            XCTAssertTrue(image.size.height.isFinite)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Home latest saved story \(size == .large ? "standard" : "accessibility")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func story(owner: String = "owner", profile: UUID? = nil, date: Date? = nil) -> MemoryEntry {
        let entry = MemoryEntry(context: persistence.container.viewContext)
        entry.id = UUID()
        entry.firebaseUserId = owner
        entry.profileID = profile ?? profileID
        entry.createdAt = date
        return entry
    }

    func testNewestStoryWinsRegardlessOfFetchOrder() {
        let older = story(date: Date(timeIntervalSince1970: 1))
        let newest = story(date: Date(timeIntervalSince1970: 2))
        let undated = story()
        XCTAssertTrue(HomeLatestStoryPolicy.latest(in: [newest, undated, older], userID: "owner", profileID: profileID) === newest)
    }

    func testOtherAccountAndProfileCannotAppearEvenWhenNewer() {
        let expected = story(date: Date(timeIntervalSince1970: 1))
        let otherAccount = story(owner: "other", date: Date(timeIntervalSince1970: 3))
        let otherProfile = story(profile: UUID(), date: Date(timeIntervalSince1970: 4))
        XCTAssertTrue(HomeLatestStoryPolicy.latest(in: [otherAccount, otherProfile, expected], userID: "owner", profileID: profileID) === expected)
        XCTAssertNil(HomeLatestStoryPolicy.latest(in: [expected], userID: nil, profileID: profileID))
        XCTAssertNil(HomeLatestStoryPolicy.latest(in: [expected], userID: "", profileID: profileID))
    }

    func testEmptyAndUnnavigableRowsDoNotProduceCard() {
        XCTAssertNil(HomeLatestStoryPolicy.latest(in: [], userID: "owner", profileID: profileID))
        let missingID = story()
        missingID.id = nil
        XCTAssertNil(HomeLatestStoryPolicy.latest(in: [missingID], userID: "owner", profileID: profileID))
        let deleted = story()
        persistence.container.viewContext.delete(deleted)
        XCTAssertNil(HomeLatestStoryPolicy.latest(in: [deleted], userID: "owner", profileID: profileID))
    }

    func testEqualDatesHaveStableSelection() {
        let first = story()
        let second = story()
        let forward = HomeLatestStoryPolicy.latest(in: [first, second], userID: "owner", profileID: profileID)
        let reverse = HomeLatestStoryPolicy.latest(in: [second, first], userID: "owner", profileID: profileID)
        XCTAssertTrue(forward === reverse)
    }

    func testTitleUsesSavedPromptWithoutUntitledPlaceholder() {
        let entry = story()
        for placeholder in ["", "   ", "Untitled", "Untitled Prompt"] {
            entry.prompt = placeholder
            XCTAssertEqual(HomeLatestStoryPolicy.title(for: entry), "Your saved story")
        }
        entry.prompt = "  The first star  "
        XCTAssertEqual(HomeLatestStoryPolicy.title(for: entry), "The first star")
    }
}
