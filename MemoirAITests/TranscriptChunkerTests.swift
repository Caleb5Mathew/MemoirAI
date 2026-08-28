import Testing
@testable import MemoirAI

struct TranscriptChunkerTests {
    @Test func oversizedSingleParagraphStaysWithinBudget() {
        let transcript = (0..<200).map { "word\($0)" }.joined(separator: " ")

        let chunks = TranscriptChunker.chunk(transcript, maxTokens: 20)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { TranscriptChunker.approximateTokenCount($0) <= 20 })
        #expect(chunks.joined(separator: " ") == transcript)
    }

    @Test func oversizedUnbrokenTextStaysWithinBudget() {
        let transcript = String(repeating: "a", count: 200)

        let chunks = TranscriptChunker.chunk(transcript, maxTokens: 5)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { TranscriptChunker.approximateTokenCount($0) <= 5 })
        #expect(chunks.joined() == transcript)
    }

    @Test func multiScalarGraphemesStayWithinMinimumBudget() {
        let transcript = String(repeating: "👨‍👩‍👧‍👦", count: 3)

        let chunks = TranscriptChunker.chunk(transcript, maxTokens: 1)

        #expect(chunks.allSatisfy { TranscriptChunker.approximateTokenCount($0) <= 1 })
        #expect(chunks.joined() == transcript)
    }

    @Test func invalidBudgetReturnsNoChunks() {
        #expect(TranscriptChunker.chunk("memoir text", maxTokens: 0).isEmpty)
    }

    @Test func paragraphBoundariesArePreservedWhenTheyFit() {
        let transcript = "First paragraph.\n\nSecond paragraph."

        #expect(TranscriptChunker.chunk(transcript, maxTokens: 100) == [transcript])
    }
}
