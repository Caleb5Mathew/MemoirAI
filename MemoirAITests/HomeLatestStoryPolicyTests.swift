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
    func testHomeProgressCountsCompletedSlotsRatherThanDuplicateRows() {
        var entries: [MemoryEntry] = []
        for chapter in allChapters.prefix(8) {
            for prompt in chapter.prompts {
                let entry = story()
                entry.chapter = chapter.title
                entry.prompt = prompt.text
                entries.append(entry)
                let duplicate = story()
                duplicate.chapter = chapter.title
                duplicate.prompt = prompt.text
                entries.append(duplicate)
            }
        }
        XCTAssertEqual(MemoirProgressPolicy.percentage(entries: entries, chapters: allChapters, childNames: [], memoirMode: .normal), 80)
    }

    func testHomeProgressRecognizesPersonalizedAndLegacyParentAnswers() throws {
        let chapter = try XCTUnwrap(allParentChapters.first { $0.number == 2 })
        let previous = try XCTUnwrap(previousParentChapters.first { $0.number == chapter.number })
        var entries: [MemoryEntry] = []
        for prompt in previous.prompts {
            for expanded in expandedChildPrompts(for: prompt, childNames: ["Maya", "Leo"]) {
                let entry = story()
                entry.chapter = chapter.title
                entry.prompt = expanded.text
                entries.append(entry)
            }
        }
        XCTAssertEqual(MemoirProgressPolicy.percentage(entries: entries, chapters: [chapter], childNames: ["Maya", "Leo"], memoirMode: .parent), 100)
        let firstPrompt = try XCTUnwrap(previous.prompts.first { $0.isPerChild })
        let missingText = firstPrompt.text.replacingOccurrences(of: "{kid}", with: "Leo")
        let partial = entries.filter { $0.prompt != missingText }
        XCTAssertEqual(MemoirProgressPolicy.percentage(entries: partial, chapters: [chapter], childNames: ["Maya", "Leo"], memoirMode: .parent), 75)
    }

    func testBookReaderSnapshotSurvivesGenerationClearingLivePages() {
        let id = UUID()
        var livePages: [StoryPageViewModel.PageItem] = [.textPage(index: 0, total: 1, body: "A saved story", title: "Title", subtitle: nil, memoryID: id)]
        let snapshot = StorybookReaderSnapshot(pages: livePages, hasExteriorCover: true)
        livePages.removeAll()
        XCTAssertEqual(snapshot.pages.count, 1)
        for slot in snapshot.slots {
            if case .interiorPage(let index) = slot {
                XCTAssertEqual(snapshot.pages[index].memoryID, id)
            }
        }
        XCTAssertTrue(livePages.isEmpty)
    }

    func testGenerationSettingsExcludePrintOrdersWhileAccountSettingsRetainThem() {
        XCTAssertFalse(SettingsContext.bookGeneration.showsPrintOrders)
        XCTAssertTrue(SettingsContext.account.showsPrintOrders)
    }

    func testReaderImageRetainsPrintOriginalAcrossUnlinkAndReplacement() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 3300, height: 2550), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3300, height: 2550))
        }
        let encoded = try XCTUnwrap(original.pngData())
        let reader = try XCTUnwrap(StorybookReaderImage.make(data: encoded))
        XCTAssertEqual(reader.cgImage?.width, 1280)
        XCTAssertLessThanOrEqual(reader.cgImage?.height ?? 0, 1280)
        XCTAssertEqual(StorybookReaderImage.originalImage(for: reader)?.cgImage?.width, 3300)
        XCTAssertEqual(StorybookReaderImage.originalData(for: reader), encoded)
        XCTAssertNil(StorybookReaderImage.originalImage(for: reader, decode: { _ in nil }),
                     "A failed original decode must never substitute the reader thumbnail")
        let sourceURL = try XCTUnwrap(StorybookReaderImage.backingURL(for: reader))
        try FileManager.default.removeItem(at: sourceURL)
        XCTAssertEqual(StorybookReaderImage.originalImage(for: reader)?.cgImage?.height, 2550,
                       "An open mapped source remains valid after its file is unlinked")
        let edited = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24), format: format).image { _ in }
        XCTAssertTrue(StorybookReaderImage.originalImage(for: edited) === edited,
                      "A replacement image must never inherit the previous print source")
        XCTAssertNil(StorybookReaderImage.backingURL(for: edited))
    }

    func testReaderSourceLifetimeAndDiskFailureKeepEncodedOriginal() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 1000), format: format).image { _ in }
        let data = try XCTUnwrap(original.pngData())
        var sourceURL: URL?
        autoreleasepool {
            let reader = StorybookReaderImage.make(data: data)
            sourceURL = reader.flatMap { StorybookReaderImage.backingURL(for: $0) }
            XCTAssertNotNil(sourceURL)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(sourceURL).path))
        let blockedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: blockedDirectory)
        defer { try? FileManager.default.removeItem(at: blockedDirectory) }
        let reader = try XCTUnwrap(StorybookReaderImage.make(data: data, directory: blockedDirectory))
        XCTAssertEqual(reader.cgImage?.width, 1280)
        XCTAssertNil(StorybookReaderImage.backingURL(for: reader))
        XCTAssertEqual(StorybookReaderImage.originalData(for: reader), data)
        XCTAssertEqual(StorybookReaderImage.originalImage(for: reader)?.cgImage?.width, 1500)
        XCTAssertNil(StorybookReaderImage.make(data: Data("invalid".utf8)))
    }

    func testFortyPageReaderBoundsDecodedPixelsAndPreservesPrintSize() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data: Data = try autoreleasepool {
            let original = UIGraphicsImageRenderer(size: CGSize(width: 3300, height: 2550), format: format).image { context in
                UIColor.systemGreen.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 3300, height: 2550))
            }
            return try XCTUnwrap(original.jpegData(compressionQuality: 0.9))
        }
        var readers: [UIImage] = []
        for _ in 0..<40 {
            let reader = try autoreleasepool { try XCTUnwrap(StorybookReaderImage.make(data: data)) }
            readers.append(reader)
            try autoreleasepool {
                let printImage = try XCTUnwrap(StorybookReaderImage.originalImage(for: reader))
                XCTAssertEqual(printImage.cgImage?.width, 3300)
                XCTAssertEqual(printImage.cgImage?.height, 2550)
            }
        }
        let decodedReaderBytes = readers.reduce(0) { sum, image in
            guard let pixels = image.cgImage else { return sum }
            return sum + pixels.bytesPerRow * pixels.height
        }
        XCTAssertEqual(readers.count, 40)
        XCTAssertGreaterThan(decodedReaderBytes, 0)
        XCTAssertLessThan(decodedReaderBytes, 210 * 1024 * 1024,
                          "This bounds decoded reader bitmap bytes, not the app's total resident memory")
        XCTAssertLessThan(decodedReaderBytes, 40 * 3300 * 2550 * 4 / 5)
    }

    func testIllustrationCacheKeepsOriginalBytesInsteadOfReaderThumbnail() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 1000), format: format).image { _ in }
        let data = try XCTUnwrap(original.pngData())
        let key = "reader-source-test-" + UUID().uuidString
        IllustrationImageDiskCache.shared.store(data: data, forKey: key)
        var cached: Data?
        for _ in 0..<100 {
            cached = IllustrationImageDiskCache.shared.data(forKey: key)
            if cached != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(cached, data)
        let restored = try XCTUnwrap(cached.flatMap { StorybookReaderImage.make(data: $0) })
        XCTAssertEqual(restored.cgImage?.width, 1280)
        XCTAssertEqual(StorybookReaderImage.originalImage(for: restored)?.cgImage?.width, 1500)
    }

}
