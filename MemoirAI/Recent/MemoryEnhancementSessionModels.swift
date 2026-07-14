import Foundation

/// One question/answer pair in a guided enhancement session.
struct MemoryEnhancementTurn: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var question: String
    var answer: String
}

/// Persisted in-progress guided enhancement (UserDefaults).
struct EnhancementSessionDraft: Codable, Equatable {
    var turns: [MemoryEnhancementTurn]
    var currentQuestion: String
    /// Restores tiered prompt context when resuming a draft (optional — older drafts omit).
    var promptContext: MemoryEnhancementPromptContext?
}

extension EnhancementSessionDraft {
    private static func key(for memoryId: UUID) -> String {
        "enhancementDraft_\(memoryId.uuidString)"
    }

    static func load(memoryId: UUID) -> EnhancementSessionDraft? {
        guard let data = UserDefaults.standard.data(forKey: key(for: memoryId)) else { return nil }
        return try? JSONDecoder().decode(EnhancementSessionDraft.self, from: data)
    }

    func save(memoryId: UUID) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(for: memoryId))
    }

    static func clear(memoryId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: memoryId))
    }
}

/// Parsed LLM decision after each user answer.
struct MemoryEnhancementTurnAnalysis: Codable {
    enum NextStep: String, Codable {
        case askNext = "ask_next"
        case extract = "extract"
    }

    var next_step: NextStep
    /// Required when `next_step` is `ask_next`; ignored for `extract`.
    var next_question: String?
    var reason: String?
}

/// Applies a hard cap on session length deterministically (testable).
enum MemoryEnhancementSessionRules {
    /// Maximum number of user answers (voice submissions) per session.
    static let maxSessionTurns = 5

    enum NextAction: Equatable {
        case askNext(question: String)
        case extract
    }

    static func resolveNextAction(
        analysis: MemoryEnhancementTurnAnalysis,
        totalTurnsCompleted: Int
    ) -> NextAction {
        if totalTurnsCompleted >= maxSessionTurns {
            return .extract
        }

        switch analysis.next_step {
        case .askNext:
            if let q = analysis.next_question?.trimmingCharacters(in: .whitespacesAndNewlines),
               !q.isEmpty {
                return .askNext(question: q)
            }
            return .extract
        case .extract:
            return .extract
        }
    }
}

enum MemoryEnhancementError: Error, Equatable {
    case missingAPIKey
    case invalidResponse
    case extractionFailed
}

// MARK: - Tiered rubric (Phase 3)

/// LLM preflight: skip Q&A when transcript is already illustration-ready, or start tiered interview.
struct MemoryEnhancementPreflight: Codable, Equatable {
    /// `"skip"` ends the session immediately (extract from transcript only). `"interview"` continues Q&A.
    var mode: String
    /// Starting tier 1...4 (T1 gender/age/ethnicity … T4 motif).
    var tier_start: Int
    /// Up to 3 names to ask about this turn (protagonist / frequent mentions first).
    var character_focus: [String]
    /// When true, jump to setting/action/mood (tier 3) — e.g. no people or pure landscape.
    var skip_people_tiers: Bool
    var rationale: String?
}

/// Passed into first-question + analyze-turn prompts so every LLM call stays on-rubric.
struct MemoryEnhancementPromptContext: Equatable, Codable {
    var tierStart: Int
    var characterFocus: [String]
    var skipPeopleTiers: Bool
}

// MARK: - LLM extraction payload (shared with MemoryEnhancementService + tests)

struct MemoryEnhancementExtractedCharacter: Codable, Equatable {
    var name: String
    var age: String?
    var gender: String?
    var ethnicity: String?
    var hairAndFeatures: String?
    var clothes: String?
    var relationshipToNarrator: String?

    enum CodingKeys: String, CodingKey {
        case name, age, gender, ethnicity
        case hairAndFeatures
        case clothes
        case relationshipToNarrator
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        age = c.decodeFlexibleString(forKey: .age)
        gender = try? c.decodeIfPresent(String.self, forKey: .gender)
        ethnicity = try? c.decodeIfPresent(String.self, forKey: .ethnicity)
        hairAndFeatures = try? c.decodeIfPresent(String.self, forKey: .hairAndFeatures)
        clothes = try? c.decodeIfPresent(String.self, forKey: .clothes)
        relationshipToNarrator = try? c.decodeIfPresent(String.self, forKey: .relationshipToNarrator)
    }
}

struct MemoryEnhancementExtractionPayload: Codable, Equatable {
    var characters: [MemoryEnhancementExtractedCharacter]
}

// MARK: - Scene spec & gap scoring (illustration readiness)

/// Person slice extracted from memory + Q&A by `parseSceneSpec`. Only fields explicitly stated or
/// clearly implied should be filled—never guessed (especially ethnicity / clothing).
struct ScenePerson: Codable, Equatable {
    var label: String
    var isNarrator: Bool
    var age: String?
    var gender: String?
    var ethnicity: String?
    var hairAndFeatures: String?
    var clothes: String?
    var relationshipToNarrator: String?

    enum CodingKeys: String, CodingKey {
        case label
        case isNarrator = "is_narrator"
        case age, gender, ethnicity
        case hairAndFeatures = "hair_and_features"
        case clothes
        case relationshipToNarrator = "relationship_to_narrator"
    }

    init(
        label: String,
        isNarrator: Bool,
        age: String?,
        gender: String?,
        ethnicity: String?,
        hairAndFeatures: String?,
        clothes: String?,
        relationshipToNarrator: String?
    ) {
        self.label = label
        self.isNarrator = isNarrator
        self.age = age
        self.gender = gender
        self.ethnicity = ethnicity
        self.hairAndFeatures = hairAndFeatures
        self.clothes = clothes
        self.relationshipToNarrator = relationshipToNarrator
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = (try c.decodeIfPresent(String.self, forKey: .label) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        isNarrator = try c.decodeIfPresent(Bool.self, forKey: .isNarrator) ?? false
        age = c.decodeFlexibleString(forKey: .age)
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        ethnicity = try c.decodeIfPresent(String.self, forKey: .ethnicity)
        hairAndFeatures = try c.decodeIfPresent(String.self, forKey: .hairAndFeatures)
        clothes = try c.decodeIfPresent(String.self, forKey: .clothes)
        relationshipToNarrator = try c.decodeIfPresent(String.self, forKey: .relationshipToNarrator)
    }
}

/// Structured “what we know” about the drawable scene. Parsed fresh each network round from memory + turns.
struct SceneSpec: Codable, Equatable {
    var hasPeople: Bool
    var people: [ScenePerson]
    var setting: String?
    var era: String?
    var action: String?
    var mood: String?
    var motif: String?
    /// True when the memory references a historical period / era but `era` is not yet known.
    var eraAppearsRelevant: Bool

    enum CodingKeys: String, CodingKey {
        case hasPeople = "has_people"
        case people
        case setting, era, action, mood, motif
        case eraAppearsRelevant = "era_appears_relevant"
    }

    init(
        hasPeople: Bool,
        people: [ScenePerson],
        setting: String?,
        era: String?,
        action: String?,
        mood: String?,
        motif: String?,
        eraAppearsRelevant: Bool = false
    ) {
        self.hasPeople = hasPeople
        self.people = people
        self.setting = setting
        self.era = era
        self.action = action
        self.mood = mood
        self.motif = motif
        self.eraAppearsRelevant = eraAppearsRelevant
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasPeople = try c.decode(Bool.self, forKey: .hasPeople)
        people = try c.decodeIfPresent([ScenePerson].self, forKey: .people) ?? []
        setting = try c.decodeIfPresent(String.self, forKey: .setting)
        era = try c.decodeIfPresent(String.self, forKey: .era)
        action = try c.decodeIfPresent(String.self, forKey: .action)
        mood = try c.decodeIfPresent(String.self, forKey: .mood)
        motif = try c.decodeIfPresent(String.self, forKey: .motif)
        eraAppearsRelevant = try c.decodeIfPresent(Bool.self, forKey: .eraAppearsRelevant) ?? false
    }
}

enum SceneGapPriority: Int, Codable, Comparable {
    case preferred = 1
    case strong = 2
    case mustHave = 3

    static func < (lhs: SceneGapPriority, rhs: SceneGapPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SceneGap: Equatable, Codable {
    enum Field: String, Codable {
        case identifyPeople
        case setting
        case action
        case ethnicity
        case era
        case hair
        case mood
        /// Narrator's age at time of memory (when unknown).
        case narratorAge
        /// Named non-narrator ages (batched in one question when possible).
        case namedPeopleAge
    }

    var field: Field
    var personLabel: String?
    var priority: SceneGapPriority
    var humanReason: String
}

/// Deterministic gap list + extract gate so we never “skip” interview while ethnicity or must-haves are missing.
enum SceneGapScorer {
    static func score(_ spec: SceneSpec, turnsCompleted _: Int, memoryText: String = "") -> [SceneGap] {
        var gaps: [SceneGap] = []
        let namedPeople = spec.people.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let memLower = memoryText.lowercased()

        if spec.hasPeople {
            if namedPeople.isEmpty {
                gaps.append(
                    SceneGap(
                        field: .identifyPeople,
                        personLabel: nil,
                        priority: .mustHave,
                        humanReason: "Who was in this memory"
                    )
                )
            }
            if isBlank(spec.setting) {
                gaps.append(
                    SceneGap(field: .setting, personLabel: nil, priority: .mustHave, humanReason: "Where this happened")
                )
            }
            if isBlank(spec.action) {
                gaps.append(
                    SceneGap(field: .action, personLabel: nil, priority: .mustHave, humanReason: "What was happening")
                )
            }
            for p in namedPeople where isBlank(p.ethnicity) {
                gaps.append(
                    SceneGap(
                        field: .ethnicity,
                        personLabel: p.label,
                        priority: ethnicityPriority(spec: spec, memoryLower: memLower),
                        humanReason: "Background or heritage for \(p.label)"
                    )
                )
            }
            if spec.eraAppearsRelevant, isBlank(spec.era) {
                gaps.append(
                    SceneGap(field: .era, personLabel: nil, priority: .strong, humanReason: "Time period")
                )
            }
            for p in namedPeople.prefix(2) where isBlank(p.hairAndFeatures) {
                gaps.append(
                    SceneGap(
                        field: .hair,
                        personLabel: p.label,
                        priority: .preferred,
                        humanReason: "Hair & features for \(p.label)"
                    )
                )
            }
            if isBlank(spec.mood) {
                gaps.append(
                    SceneGap(field: .mood, personLabel: nil, priority: .preferred, humanReason: "Mood of the moment")
                )
            }

            if let narrator = namedPeople.first(where: { $0.isNarrator }),
               isBlank(narrator.age),
               !memoryTextHasExplicitNarratorAge(memoryText) {
                gaps.append(
                    SceneGap(
                        field: .narratorAge,
                        personLabel: narrator.label,
                        priority: narratorAgePriority(spec: spec, memoryLower: memLower),
                        humanReason: "Roughly how old was the narrator (\(narrator.label)) in this memory"
                    )
                )
            }

            let narrAgeResolved = narratorAgeKnown(spec: spec, memoryText: memoryText)
            let nonNarrWithoutAge = namedPeople.filter { !$0.isNarrator && isBlank($0.age) && !relationshipImpliesAge($0) }
            if nonNarrWithoutAge.count >= 3 {
                for p in nonNarrWithoutAge {
                    gaps.append(
                        SceneGap(
                            field: .namedPeopleAge,
                            personLabel: p.label,
                            priority: namedPeopleAgePriority(narratorAgeKnown: narrAgeResolved),
                            humanReason: "Roughly how old was \(p.label)"
                        )
                    )
                }
            }
        } else {
            if isBlank(spec.setting) {
                gaps.append(
                    SceneGap(field: .setting, personLabel: nil, priority: .mustHave, humanReason: "Setting")
                )
            }
            if isBlank(spec.action) {
                gaps.append(
                    SceneGap(field: .action, personLabel: nil, priority: .mustHave, humanReason: "What was happening")
                )
            }
            if spec.eraAppearsRelevant, isBlank(spec.era) {
                gaps.append(
                    SceneGap(field: .era, personLabel: nil, priority: .strong, humanReason: "Time period")
                )
            }
            if isBlank(spec.mood) {
                gaps.append(
                    SceneGap(field: .mood, personLabel: nil, priority: .preferred, humanReason: "Mood or atmosphere")
                )
            }
        }

        return gaps
    }

    static func sortedGaps(_ gaps: [SceneGap]) -> [SceneGap] {
        gaps.sorted { a, b in
            if a.priority != b.priority {
                return a.priority > b.priority
            }
            if gapFieldSortIndex(a.field) != gapFieldSortIndex(b.field) {
                return gapFieldSortIndex(a.field) < gapFieldSortIndex(b.field)
            }
            return (a.personLabel ?? "") < (b.personLabel ?? "")
        }
    }

    /// Whether to run extraction now (no more questions), given remaining gaps and how many answers we already have.
    static func shouldExtract(gaps: [SceneGap], turnsCompleted: Int) -> Bool {
        if turnsCompleted >= MemoryEnhancementSessionRules.maxSessionTurns {
            return true
        }
        if gaps.contains(where: { $0.priority == .mustHave }) {
            return false
        }
        if gaps.contains(where: { $0.priority == .strong }), turnsCompleted < 3 {
            return false
        }
        if gaps.contains(where: { $0.priority == .preferred }), turnsCompleted < 2 {
            return false
        }
        return true
    }

    /// Bundle gaps into one user-facing question (multi-ethnicity batching, etc.).
    static func gapsToTargetForQuestion(_ sorted: [SceneGap]) -> [SceneGap] {
        guard let first = sorted.first else { return [] }

        if first.field == .narratorAge {
            return [first]
        }

        if first.field == .namedPeopleAge {
            var bundle: [SceneGap] = []
            for g in sorted where g.field == .namedPeopleAge && bundle.count < 3 {
                bundle.append(g)
            }
            return bundle
        }

        if first.field == .ethnicity {
            var bundle: [SceneGap] = []
            for g in sorted where g.field == .ethnicity && bundle.count < 3 {
                bundle.append(g)
            }
            // Single named person: optionally bundle hair + features with ethnicity.
            if bundle.count == 1, let label = bundle[0].personLabel,
               let hair = sorted.first(where: { $0.field == .hair && $0.personLabel == label }) {
                bundle.append(hair)
            }
            return bundle
        }

        var bundle = [first]

        if (first.field == .setting && sorted.dropFirst().first?.field == .action) ||
            (first.field == .action && sorted.dropFirst().first?.field == .setting) {
            if let second = sorted.dropFirst().first,
               (second.field == .setting || second.field == .action),
               second.priority == first.priority {
                bundle.append(second)
            }
        }

        return bundle
    }

    private static func isBlank(_ s: String?) -> Bool {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func gapFieldSortIndex(_ f: SceneGap.Field) -> Int {
        switch f {
        case .identifyPeople: return 0
        case .setting: return 1
        case .action: return 2
        case .ethnicity: return 3
        case .narratorAge: return 4
        case .namedPeopleAge: return 5
        case .era: return 6
        case .hair: return 7
        case .mood: return 8
        }
    }

    private static func memoryTextHasExplicitNarratorAge(_ memoryText: String) -> Bool {
        let lower = memoryText.lowercased()
        if lower.range(of: #"\b(?:i was|when i was|at age|age|turned|turning)\s+\d{1,2}\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b\d{1,2}\s*(?:years old|year old|yrs old)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b(?:i was|when i was)\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\bin my (?:early|mid|late)\s*(?:20|30|40|50|60)s\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func culturalMarkersPresent(spec: SceneSpec, memoryLower: String) -> Bool {
        let blob = [spec.setting, spec.action, spec.motif, memoryLower]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let keys = [
            "eid", "diwali", "holi", "ramadan", "passover", "pesach", "quinceañera", "quinceanera",
            "lunar new year", "chinese new year", "hanukkah", "chanukah", "bar mitzvah", "bat mitzvah",
            "día de los muertos", "dia de los muertos", "nowruz", "vesak", "vesak day", "baptism", "nikah",
            "wedding"
        ]
        return keys.contains { blob.contains($0) }
    }

    private static func ethnicityPriority(spec: SceneSpec, memoryLower: String) -> SceneGapPriority {
        if culturalMarkersPresent(spec: spec, memoryLower: memoryLower) {
            return .mustHave
        }
        return .strong
    }

    private static func lifeStageCueSuggestsAge(_ memoryLower: String) -> Bool {
        let cues = [
            "college", "university", "freshman", "sophomore", "junior year", "senior year",
            "high school", "middle school", "kindergarten", "elementary school",
            "first job", "retired", "retirement", "grandchild", "grandmother", "grandfather",
            "became a parent", "had a baby", "had my first"
        ]
        return cues.contains { memoryLower.contains($0) }
    }

    private static func narratorAgePriority(spec: SceneSpec, memoryLower: String) -> SceneGapPriority {
        if lifeStageCueSuggestsAge(memoryLower) { return .mustHave }
        if spec.eraAppearsRelevant { return .strong }
        return .preferred
    }

    private static func narratorAgeKnown(spec: SceneSpec, memoryText: String) -> Bool {
        if memoryTextHasExplicitNarratorAge(memoryText) { return true }
        if let n = spec.people.first(where: { $0.isNarrator }), let a = n.age, !isBlank(a) { return true }
        return false
    }

    private static func namedPeopleAgePriority(narratorAgeKnown: Bool) -> SceneGapPriority {
        narratorAgeKnown ? .strong : .preferred
    }

    private static func relationshipImpliesAge(_ p: ScenePerson) -> Bool {
        let r = (p.relationshipToNarrator ?? "").lowercased()
        let keys = [
            "grandmother", "grandfather", "grandma", "grandpa", "nana", "papa", "toddler",
            "infant", "baby", "newborn", "teenager", "little kid", "preschool"
        ]
        return keys.contains { r.contains($0) }
    }
}

private extension KeyedDecodingContainer {
    /// Decodes an optional String that the LLM may return as a number.
    /// Tries String first; falls back to Int then Double, converting to String.
    func decodeFlexibleString(forKey key: Key) -> String? {
        guard contains(key) else { return nil }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let n = try? decodeIfPresent(Int.self, forKey: key) { return String(n) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) {
            return d == Double(Int(d)) ? String(Int(d)) : String(d)
        }
        return nil
    }
}

/// First guided question + UI subtitle from gap-targeted generation.
struct GapQuestionBundle: Codable, Equatable {
    var question: String
    var caption: String
}

extension CharacterDetails {
    /// Builds character cards from the extraction JSON returned by the LLM.
    static func fromExtractionPayload(_ payload: MemoryEnhancementExtractionPayload) -> CharacterDetails {
        var out = CharacterDetails()
        for c in payload.characters {
            var ch = CharacterDetails.Character()
            ch.name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
            ch.age = (c.age ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ch.gender = (c.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ch.ethnicity = (c.ethnicity ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ch.hairAndFeatures = (c.hairAndFeatures ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ch.clothes = (c.clothes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ch.relationshipToNarrator = (c.relationshipToNarrator ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ch.name.isEmpty else { continue }
            out.characters.append(ch)
        }
        return out
    }

    static func fromExtractionJSONData(_ data: Data) throws -> CharacterDetails {
        let payload = try JSONDecoder().decode(MemoryEnhancementExtractionPayload.self, from: data)
        return fromExtractionPayload(payload)
    }
}
