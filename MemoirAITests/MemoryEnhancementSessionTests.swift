//
//  MemoryEnhancementSessionTests.swift
//  MemoirAITests
//

import Testing
@testable import MemoirAI

struct MemoryEnhancementSessionTests {

    @Test func sessionRules_askNextWhenValid() {
        let analysis = MemoryEnhancementTurnAnalysis(
            next_step: .askNext,
            next_question: "What were they wearing?",
            reason: nil
        )
        let r = MemoryEnhancementSessionRules.resolveNextAction(
            analysis: analysis,
            totalTurnsCompleted: 2
        )
        guard case .askNext(let q) = r else {
            Issue.record("Expected askNext")
            return
        }
        #expect(q == "What were they wearing?")
    }

    @Test func sessionRules_askNextMissingQuestionFallsBackToExtract() {
        let analysis = MemoryEnhancementTurnAnalysis(
            next_step: .askNext,
            next_question: "   ",
            reason: nil
        )
        let r = MemoryEnhancementSessionRules.resolveNextAction(
            analysis: analysis,
            totalTurnsCompleted: 1
        )
        guard case .extract = r else {
            Issue.record("Expected extract when next_question empty")
            return
        }
    }

    @Test func sessionRules_extractFromModel() {
        let analysis = MemoryEnhancementTurnAnalysis(
            next_step: .extract,
            next_question: nil,
            reason: nil
        )
        let r = MemoryEnhancementSessionRules.resolveNextAction(
            analysis: analysis,
            totalTurnsCompleted: 2
        )
        guard case .extract = r else {
            Issue.record("Expected extract")
            return
        }
    }

    @Test func sessionRules_totalTurnCapForcesExtract() {
        let analysis = MemoryEnhancementTurnAnalysis(
            next_step: .askNext,
            next_question: "More detail?",
            reason: nil
        )
        let r = MemoryEnhancementSessionRules.resolveNextAction(
            analysis: analysis,
            totalTurnsCompleted: MemoryEnhancementSessionRules.maxSessionTurns
        )
        guard case .extract = r else {
            Issue.record("Expected extract at session turn cap")
            return
        }
    }

    @Test func characterDetailsMerging_appendsNewNames() {
        var a = CharacterDetails.Character()
        a.name = "Ruth"
        a.age = "70"
        var b = CharacterDetails.Character()
        b.name = "Sam"
        b.gender = "male"
        let merged = CharacterDetails.merging(
            existing: CharacterDetails(characters: [a]),
            incoming: CharacterDetails(characters: [b])
        )
        #expect(merged.characters.count == 2)
        let names = Set(merged.characters.map { $0.name })
        #expect(names == ["Ruth", "Sam"])
    }

    @Test func characterDetailsMerging_mergesSameNamePrefersIncomingNonEmpty() {
        var existing = CharacterDetails.Character()
        existing.name = "Ruth"
        existing.age = "70"
        existing.hairAndFeatures = "gray hair"
        var incoming = CharacterDetails.Character()
        incoming.name = "ruth"
        incoming.age = "72"
        incoming.clothes = "blue sweater"
        let merged = CharacterDetails.merging(
            existing: CharacterDetails(characters: [existing]),
            incoming: CharacterDetails(characters: [incoming])
        )
        #expect(merged.characters.count == 1)
        #expect(merged.characters[0].age == "72")
        #expect(merged.characters[0].hairAndFeatures.contains("gray"))
        #expect(merged.characters[0].clothes.contains("sweater"))
    }

    @Test func characterDetailsMerging_incomingEmptyReturnsExisting() {
        var existing = CharacterDetails.Character()
        existing.name = "Ruth"
        let merged = CharacterDetails.merging(
            existing: CharacterDetails(characters: [existing]),
            incoming: CharacterDetails()
        )
        #expect(merged.characters.count == 1)
        #expect(merged.characters[0].name == "Ruth")
    }

    @Test func extractionJSON_mapsToCharacterDetails() throws {
        let json = """
        {"characters":[{"name":"Ruth","age":"72","gender":"female","ethnicity":"","hairAndFeatures":"short gray hair","clothes":"red cardigan","relationshipToNarrator":"grandmother"}]}
        """
        guard let data = json.data(using: .utf8) else {
            Issue.record("UTF-8 data expected")
            return
        }
        let details = try CharacterDetails.fromExtractionJSONData(data)
        #expect(details.characters.count == 1)
        #expect(details.characters[0].name == "Ruth")
        #expect(details.characters[0].hairAndFeatures.contains("gray"))
        #expect(details.characters[0].clothes.contains("cardigan"))
    }
}
