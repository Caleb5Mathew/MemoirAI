import CoreData
import Testing
@testable import MemoirAI

@MainActor
struct StorybookMemoryEligibilityTests {
    @Test func includesWrittenAndRecordedStoriesWithoutAChapter() {
        let persistence = PersistenceController(inMemory: true)
        let entry = MemoryEntry(context: persistence.container.viewContext)
        entry.chapter = nil
        entry.text = "A memory from our first family holiday."
        #expect(StorybookMemoryEligibilityPolicy.matches(entry))
        entry.text = nil
        entry.audioFileURL = "https://example.invalid/recording.m4a"
        entry.transcriptionStatus = "failed"
        #expect(StorybookMemoryEligibilityPolicy.matches(entry))
        entry.audioFileURL = "  "
        #expect(!StorybookMemoryEligibilityPolicy.matches(entry))
        entry.chapter = "Growing Up"
        #expect(!StorybookMemoryEligibilityPolicy.matches(entry))
    }
}
