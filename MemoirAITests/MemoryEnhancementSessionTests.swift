//
//  MemoryEnhancementSessionTests.swift
//  MemoirAITests
//

import Testing
@testable import MemoirAI

struct MemoryEnhancementSessionTests {

    // MARK: - Narrator profile-fact seeding

    private func makePerson(
        label: String,
        isNarrator: Bool,
        ethnicity: String? = nil,
        hairAndFeatures: String? = nil
    ) -> ScenePerson {
        ScenePerson(
            label: label,
            isNarrator: isNarrator,
            age: nil,
            gender: nil,
            ethnicity: ethnicity,
            hairAndFeatures: hairAndFeatures,
            clothes: nil,
            relationshipToNarrator: nil
        )
    }

    @Test func narratorFactsSeeding_fillsOnlyNarratorBlanks() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [
                makePerson(label: "Martha", isNarrator: true),
                makePerson(label: "Sam", isNarrator: false)
            ],
            setting: "kitchen",
            era: nil,
            action: "baking",
            mood: nil,
            motif: nil
        )
        let facts = NarratorProfileFacts(gender: "Female", ethnicity: "Irish", hairAndFeatures: "curly gray hair")
        let seeded = spec.seedingNarratorFacts(facts)
        #expect(seeded.people[0].ethnicity == "Irish")
        #expect(seeded.people[0].gender == "Female")
        #expect(seeded.people[0].hairAndFeatures == "curly gray hair")
        #expect(seeded.people[1].ethnicity == nil)
        #expect(seeded.people[1].hairAndFeatures == nil)
    }

    @Test func narratorFactsSeeding_neverOverwritesExtractedValues() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [makePerson(label: "Martha", isNarrator: true, ethnicity: "Italian", hairAndFeatures: "short bob")],
            setting: nil,
            era: nil,
            action: nil,
            mood: nil,
            motif: nil
        )
        let facts = NarratorProfileFacts(gender: nil, ethnicity: "Irish", hairAndFeatures: "curly gray hair")
        let seeded = spec.seedingNarratorFacts(facts)
        #expect(seeded.people[0].ethnicity == "Italian")
        #expect(seeded.people[0].hairAndFeatures == "short bob")
    }

    @Test func narratorFactsSeeding_removesNarratorEthnicityGapFromScorer() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [makePerson(label: "Martha", isNarrator: true)],
            setting: "kitchen",
            era: nil,
            action: "baking",
            mood: "joyful",
            motif: nil
        )
        let facts = NarratorProfileFacts(gender: "Female", ethnicity: "Irish", hairAndFeatures: "curly gray hair")

        let gapsBefore = SceneGapScorer.score(spec, turnsCompleted: 0, memoryText: "Baking bread.")
        #expect(gapsBefore.contains { $0.field == .ethnicity && $0.personLabel == "Martha" })

        let gapsAfter = SceneGapScorer.score(spec.seedingNarratorFacts(facts), turnsCompleted: 0, memoryText: "Baking bread.")
        #expect(!gapsAfter.contains { $0.field == .ethnicity && $0.personLabel == "Martha" })
        #expect(!gapsAfter.contains { $0.field == .hair && $0.personLabel == "Martha" })
    }

    @Test func narratorFactsSeeding_noOpWhenFactsEmpty() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [makePerson(label: "Martha", isNarrator: true)],
            setting: nil,
            era: nil,
            action: nil,
            mood: nil,
            motif: nil
        )
        let empty = NarratorProfileFacts(gender: "  ", ethnicity: "", hairAndFeatures: nil)
        #expect(spec.seedingNarratorFacts(empty) == spec)
        #expect(spec.seedingNarratorFacts(nil) == spec)
    }

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

    // MARK: - Scene gap scorer

    private func person(
        _ label: String,
        ethnicity: String? = nil,
        hair: String? = nil
    ) -> ScenePerson {
        ScenePerson(
            label: label,
            isNarrator: false,
            age: nil,
            gender: nil,
            ethnicity: ethnicity,
            hairAndFeatures: hair,
            clothes: nil,
            relationshipToNarrator: nil
        )
    }

    @Test func sceneGapScorer_namedPeopleMissingEthnicity_shouldNotExtractAtTurn0() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [person("Bob"), person("Sam")],
            setting: "park",
            era: nil,
            action: "playing catch",
            mood: "happy",
            motif: nil,
            eraAppearsRelevant: false
        )
        let gaps = SceneGapScorer.score(spec, turnsCompleted: 0)
        #expect(gaps.contains { $0.field == .ethnicity })
        #expect(SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: 0) == false)
    }

    @Test func sceneGapScorer_fullySpecified_shouldExtractAtTurn0() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [
                person("Bob", ethnicity: "Mexican American", hair: "short curly hair")
            ],
            setting: "kitchen",
            era: nil,
            action: "baking cookies",
            mood: "warm",
            motif: nil,
            eraAppearsRelevant: false
        )
        let gaps = SceneGapScorer.score(spec, turnsCompleted: 0)
        #expect(SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: 0) == true)
    }

    @Test func sceneGapScorer_sceneryOnly_shouldExtractWhenSettingAndActionPresent() {
        let spec = SceneSpec(
            hasPeople: false,
            people: [],
            setting: "old barn at sunset",
            era: nil,
            action: "swallows nesting in the rafters",
            mood: "quiet",
            motif: nil,
            eraAppearsRelevant: false
        )
        let gaps = SceneGapScorer.score(spec, turnsCompleted: 0)
        #expect(SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: 0) == true)
    }

    @Test func sceneGapScorer_turnCapForcesExtractEvenWithStrongGaps() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [person("Lee")],
            setting: "school",
            era: nil,
            action: "walking home",
            mood: nil,
            motif: nil,
            eraAppearsRelevant: false
        )
        let gaps = SceneGapScorer.score(spec, turnsCompleted: 0)
        #expect(gaps.contains { $0.field == .ethnicity })
        #expect(SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: MemoryEnhancementSessionRules.maxSessionTurns) == true)
    }

    @Test func sceneGapScorer_strongGapsStopBlockingAfterTurn3() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [person("Alex")],
            setting: "café",
            era: nil,
            action: "talking",
            mood: nil,
            motif: nil,
            eraAppearsRelevant: false
        )
        let gaps = SceneGapScorer.score(spec, turnsCompleted: 0)
        #expect(SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: 0) == false)
        #expect(SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: 3) == true)
    }

    @Test func sceneGapScorer_sortedGaps_mustHaveBeforeEthnicity() {
        let spec = SceneSpec(
            hasPeople: true,
            people: [person("Pat")],
            setting: "",
            era: nil,
            action: "",
            mood: nil,
            motif: nil,
            eraAppearsRelevant: false
        )
        let sorted = SceneGapScorer.sortedGaps(SceneGapScorer.score(spec, turnsCompleted: 0))
        #expect(sorted.first?.field == .setting || sorted.first?.field == .action)
    }

    @Test func characterCardNormalization_rewritesNarratorAliases() {
        var a = CharacterDetails.Character()
        a.name = "I"
        a.relationshipToNarrator = "memoir narrator"
        var details = CharacterDetails(characters: [a])
        details.normalizeCardDisplayNames(profileDisplayName: "Caleb", relationshipStyleProfileName: false)
        #expect(details.characters[0].name == "Caleb")
    }

    @Test func characterCardNormalization_motherPlusWifeDisambiguates() {
        var a = CharacterDetails.Character()
        a.name = "Mother"
        a.relationshipToNarrator = "wife"
        var details = CharacterDetails(characters: [a])
        details.normalizeCardDisplayNames(profileDisplayName: "Alex", relationshipStyleProfileName: false)
        #expect(details.characters[0].name.contains("Mother"))
        #expect(details.characters[0].name.lowercased().contains("narrator's wife"))
    }

    @Test func characterCardNormalization_memoirNarratorRelRewritesMomToProfileName() {
        var a = CharacterDetails.Character()
        a.name = "Mom"
        a.relationshipToNarrator = "memoir narrator"
        var details = CharacterDetails(characters: [a])
        details.normalizeCardDisplayNames(profileDisplayName: "Pat", relationshipStyleProfileName: false)
        #expect(details.characters[0].name == "Pat")
    }

    @Test func characterCardNormalization_memoirNarratorRelRewritesMomToTheMemoirNarrator() {
        var a = CharacterDetails.Character()
        a.name = "Mom"
        a.relationshipToNarrator = "memoir narrator"
        var details = CharacterDetails(characters: [a])
        details.normalizeCardDisplayNames(profileDisplayName: "Grandparent", relationshipStyleProfileName: true)
        #expect(details.characters[0].name == "the memoir narrator")
    }
}
