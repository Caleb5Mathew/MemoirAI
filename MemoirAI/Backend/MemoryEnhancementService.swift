import Foundation

/// OpenAI-backed analysis + extraction for guided memory enhancement.
actor MemoryEnhancementService {
    init() {}

    static func fromMainBundle() -> MemoryEnhancementService? {
        MemoryEnhancementService()
    }

    /// Preflight: parse the scene, score illustration gaps, skip Q&A only when nothing important is missing.
    func runPreflight(memoryTitle: String?, memoryText: String) async throws -> MemoryEnhancementPreflight {
        do {
            let spec = try await parseSceneSpec(memoryTitle: memoryTitle, memoryText: memoryText, turns: [])
            let gaps = SceneGapScorer.sortedGaps(SceneGapScorer.score(spec, turnsCompleted: 0, memoryText: memoryText))
            if SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: 0) {
                return MemoryEnhancementPreflight(
                    mode: "skip",
                    tier_start: 1,
                    character_focus: [],
                    skip_people_tiers: !spec.hasPeople,
                    rationale: "scene_ready"
                )
            }
            let named = spec.people.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let focus = Array(named.prefix(3).map(\.label))
            let body = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackNames = Array(CharacterCanonHelper.capitalizedNameCandidates(in: body).prefix(3))
            return MemoryEnhancementPreflight(
                mode: "interview",
                tier_start: 1,
                character_focus: focus.isEmpty ? fallbackNames : focus,
                skip_people_tiers: !spec.hasPeople,
                rationale: nil
            )
        } catch {
            let body = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
            return MemoryEnhancementPreflight(
                mode: "interview",
                tier_start: 1,
                character_focus: Array(CharacterCanonHelper.capitalizedNameCandidates(in: body).prefix(3)),
                skip_people_tiers: !CharacterCanonHelper.likelyPeoplePresent(in: body),
                rationale: "parse_fallback"
            )
        }
    }

    /// First interview question — gap-targeted from parsed scene spec.
    func generateFirstQuestion(
        memoryTitle: String?,
        memoryText: String,
        context: MemoryEnhancementPromptContext
    ) async throws -> GapQuestionBundle {
        _ = context
        let spec = try await parseSceneSpec(memoryTitle: memoryTitle, memoryText: memoryText, turns: [])
        let gaps = SceneGapScorer.sortedGaps(SceneGapScorer.score(spec, turnsCompleted: 0, memoryText: memoryText))
        guard !gaps.isEmpty, !SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: 0) else {
            throw MemoryEnhancementError.invalidResponse
        }
        let target = SceneGapScorer.gapsToTargetForQuestion(gaps)
        guard !target.isEmpty else { throw MemoryEnhancementError.invalidResponse }
        return try await generateGapTargetedQuestion(
            memoryTitle: memoryTitle,
            memoryText: memoryText,
            turns: [],
            spec: spec,
            targetGaps: target
        )
    }

    func analyzeTurn(
        memoryTitle: String?,
        memoryText: String,
        turns: [MemoryEnhancementTurn],
        context: MemoryEnhancementPromptContext
    ) async throws -> MemoryEnhancementTurnAnalysis {
        _ = context
        let spec = try await parseSceneSpec(memoryTitle: memoryTitle, memoryText: memoryText, turns: turns)
        let gaps = SceneGapScorer.sortedGaps(SceneGapScorer.score(spec, turnsCompleted: turns.count, memoryText: memoryText))
        if gaps.isEmpty || SceneGapScorer.shouldExtract(gaps: gaps, turnsCompleted: turns.count) {
            return MemoryEnhancementTurnAnalysis(next_step: .extract, next_question: nil, reason: nil)
        }
        let target = SceneGapScorer.gapsToTargetForQuestion(gaps)
        guard !target.isEmpty else {
            return MemoryEnhancementTurnAnalysis(next_step: .extract, next_question: nil, reason: nil)
        }
        let bundle = try await generateGapTargetedQuestion(
            memoryTitle: memoryTitle,
            memoryText: memoryText,
            turns: turns,
            spec: spec,
            targetGaps: target
        )
        return MemoryEnhancementTurnAnalysis(
            next_step: .askNext,
            next_question: bundle.question,
            reason: bundle.caption
        )
    }

    func extractStructuredDetails(
        memoryTitle: String?,
        memoryText: String,
        turns: [MemoryEnhancementTurn],
        profileDisplayName: String? = nil,
        relationshipStyleProfileName: Bool = false
    ) async throws -> CharacterDetails {
        let spec = try await parseSceneSpec(memoryTitle: memoryTitle, memoryText: memoryText, turns: turns)
        let qa = turns.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        let specBlock = Self.formatSceneSpecForPrompt(spec)
        let title = (memoryTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let system = """
        From the memory, the confirmed SCENE SPEC below, and interview Q&A, build character cards for illustration.

        The SCENE SPEC is the single source of truth for what was explicitly stated or clearly implied. Copy ethnicity, hair, clothes, age, gender, and relationship strings **verbatim** from the spec when present. Use memory text + Q&A only to split combined answers into fields or to add detail the spec omitted.

        Rules:
        - Output ONLY JSON: {"characters":[...]}.
        - Each character: name (required string), age, gender, ethnicity, hairAndFeatures, clothes, relationshipToNarrator (strings; use "" if unknown).
        - Do NOT invent names or traits not grounded in the spec, memory, or answers; leave fields empty when unknown.
        - **Anti-hallucination (critical):** Leave `gender`, `ethnicity`, `hairAndFeatures`, `clothes`, and `age` as empty strings when the memory text, SCENE SPEC, or Q&A does not state or clearly imply them. Do NOT infer them from cultural priors, names, relationship labels, or stereotypes. Empty is the correct answer when unknown.
        - Merge duplicates (same person).
        - If has_people is false in the spec, return {"characters":[]}.
        - If the SCENE SPEC marks one person with is_narrator true, that character must use relationshipToNarrator exactly "memoir narrator" (so cloud generation can read narrator age from character cards).
        """
        let user = """
        Title: \(title.isEmpty ? "(none)" : title)

        SCENE SPEC (authoritative):
        \(specBlock)

        Original memory:
        \(memoryText.prefix(2500))

        Interview Q&A:
        \(qa.isEmpty ? "(none)" : qa)
        """
        var dto: MemoryEnhancementExtractionPayload = try await postJSONExtraction(system: system, user: user)
        Self.applyMemoirNarratorRelationshipMarker(spec: spec, payload: &dto)
        var details = CharacterDetails.fromExtractionPayload(dto)
        details.normalizeCardDisplayNames(
            profileDisplayName: profileDisplayName,
            relationshipStyleProfileName: relationshipStyleProfileName
        )
        return details
    }

    /// Ensures cloud image ranking can read narrator age from `characterDetails` even if the extraction model omits the marker.
    private static func applyMemoirNarratorRelationshipMarker(spec: SceneSpec, payload: inout MemoryEnhancementExtractionPayload) {
        let narratorLabels = spec.people.filter { $0.isNarrator }.map {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty }
        guard !narratorLabels.isEmpty else { return }
        let labelSet = Set(narratorLabels)
        for i in payload.characters.indices {
            let nm = payload.characters[i].name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard labelSet.contains(nm) else { continue }
            payload.characters[i].relationshipToNarrator = "memoir narrator"
        }
    }

    // MARK: - Scene parsing & gap questions

    private func parseSceneSpec(
        memoryTitle: String?,
        memoryText: String,
        turns: [MemoryEnhancementTurn]
    ) async throws -> SceneSpec {
        let title = (memoryTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let qa = turns.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        let system = """
        Extract a structured scene specification for **illustrating** one memoir memory, optionally with follow-up interview answers.

        Rules:
        - Only fill a field when the user stated it clearly OR it is unambiguously implied (e.g. "Grandma" implies an older woman — still do not invent a specific age).
        - NEVER guess ethnicity, skin tone, hair color, or clothing. Leave null/empty when not grounded.
        - **Do NOT infer `gender` (or ethnicity, hair, clothes, age) from names, relationship words, or cultural priors.** If the user did not state it, leave those fields null/empty.
        - has_people: false only when there are no humans in the scene (pure landscape/object/still-life). If "I" or named people appear, has_people is true.
        - people: one entry per distinct person with a short label (given name OR relationship like "Mom"). Mark is_narrator true for the first-person voice when applicable. For anyone marked is_narrator true, set relationship_to_narrator to "memoir narrator" once that identity is known (or null until then).
        - era_appears_relevant: true when a historical war, decade, or period is central to how the scene should look and era is not yet known from text.

        Return ONLY JSON with keys:
        has_people (bool),
        people (array of { "label", "is_narrator", "age", "gender", "ethnicity", "hair_and_features", "clothes", "relationship_to_narrator" } — use null for unknown strings),
        setting, era, action, mood, motif (nullable strings),
        era_appears_relevant (bool).
        """
        let user = """
        Title: \(title.isEmpty ? "(none)" : title)

        Memory:
        \(body.isEmpty ? "(empty)" : String(body.prefix(2800)))

        Interview Q&A (may be empty):
        \(qa.isEmpty ? "(none)" : String(qa.prefix(4000)))
        """
        return try await postJSONDecoding(system: system, user: user, maxTokens: 1200, temperature: 0.1)
    }

    private func generateGapTargetedQuestion(
        memoryTitle: String?,
        memoryText: String,
        turns: [MemoryEnhancementTurn],
        spec: SceneSpec,
        targetGaps: [SceneGap]
    ) async throws -> GapQuestionBundle {
        let title = (memoryTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let qa = turns.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        let specBlock = Self.formatSceneSpecForPrompt(spec)
        let gapLines = targetGaps.map { gap in
            "- [\(gap.priority)] \(gap.field.rawValue)\(gap.personLabel.map { " (\($0))" } ?? "") — \(gap.humanReason)"
        }.joined(separator: "\n")
        let captionFallback = targetGaps.map(\.humanReason).joined(separator: " · ")
        let peopleNonEmpty = !spec.people.isEmpty

        let system = """
        You write ONE warm, open-ended interview question (~40 words max) to fill illustration gaps for a memoir app.

        Confirmed facts — **never ask the user to repeat these**:
        \(specBlock)

        Target gaps — bundle ONLY these into a single question:
        \(gapLines)

        Rules:
        - Do not ask who else was present if `people` is already non-empty unless the gap list explicitly includes identifyPeople.
        - Do not ask for plot, backstory, or why relationships matter.
        - No yes/no questions.
        - Phrase heritage / ethnicity / background questions respectfully and optionally (users may decline).
        - Keep it one question; if multiple people lack ethnicity, ask once for up to those names together.
        - For narratorAge gaps: ask once, plainly (e.g. "Roughly how old were you in this memory?"). Accept ranges like "early 20s" or "around 30"; never demand an exact integer.
        - For namedPeopleAge gaps: ask once for the listed names together (up to three people), e.g. "Roughly how old were Alex, Sam, and Jordan—teens, 20s, 30s is fine." Do not combine narrator age and friend ages in the same question.
        - Age questions should feel optional; accept "not sure" or rough guesses.

        Return ONLY JSON: {"question":"...","caption":"short subtitle for UI, under 72 characters"}
        """
        let user = """
        Title: \(title.isEmpty ? "(none)" : title)

        Memory:
        \(body.isEmpty ? "(empty)" : String(body.prefix(2500)))

        Interview so far:
        \(qa.isEmpty ? "(none yet)" : String(qa.prefix(3500)))

        Context: people list non-empty = \(peopleNonEmpty)
        """
        struct DTO: Codable {
            var question: String
            var caption: String?
        }
        let dto: DTO = try await postJSONDecoding(system: system, user: user, maxTokens: 320, temperature: 0.25)
        let q = dto.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw MemoryEnhancementError.invalidResponse }
        let cap = (dto.caption ?? captionFallback).trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = cap.isEmpty ? captionFallback : cap
        return GapQuestionBundle(question: q, caption: caption)
    }

    private static func formatSceneSpecForPrompt(_ spec: SceneSpec) -> String {
        var lines: [String] = []
        lines.append("has_people: \(spec.hasPeople)")
        lines.append("era_appears_relevant: \(spec.eraAppearsRelevant)")
        if spec.hasPeople {
            if spec.people.isEmpty {
                lines.append("people: (none listed yet)")
            } else {
                lines.append("people:")
                for p in spec.people {
                    let bits = [
                        "label=\(p.label)",
                        "narrator=\(p.isNarrator)",
                        "age=\(p.age ?? "")",
                        "gender=\(p.gender ?? "")",
                        "ethnicity=\(p.ethnicity ?? "")",
                        "hair=\(p.hairAndFeatures ?? "")",
                        "clothes=\(p.clothes ?? "")",
                        "relationship=\(p.relationshipToNarrator ?? "")"
                    ].joined(separator: ", ")
                    lines.append("  - \(bits)")
                }
            }
        }
        lines.append("setting: \(spec.setting ?? "")")
        lines.append("era: \(spec.era ?? "")")
        lines.append("action: \(spec.action ?? "")")
        lines.append("mood: \(spec.mood ?? "")")
        lines.append("motif: \(spec.motif ?? "")")
        return lines.joined(separator: "\n")
    }

    // MARK: - Networking

    private func postJSONDecoding<T: Decodable>(
        system: String,
        user: String,
        maxTokens: Int = 220,
        temperature: Double = 0.2
    ) async throws -> T {
        let raw = try await performChat(system: system, user: user, maxTokens: maxTokens, temperature: temperature, promptChars: user.count)
        guard let jsonStart = raw.firstIndex(of: "{"),
              let jsonEnd = raw.lastIndex(of: "}") else {
            throw MemoryEnhancementError.invalidResponse
        }
        let slice = String(raw[jsonStart...jsonEnd])
        guard let jsonData = slice.data(using: .utf8) else {
            throw MemoryEnhancementError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    private func postJSONExtraction(system: String, user: String) async throws -> MemoryEnhancementExtractionPayload {
        let raw = try await performChat(system: system, user: user, maxTokens: 1200, temperature: 0.15, promptChars: user.count)
        guard let jsonStart = raw.firstIndex(of: "{"),
              let jsonEnd = raw.lastIndex(of: "}") else {
            throw MemoryEnhancementError.invalidResponse
        }
        let slice = String(raw[jsonStart...jsonEnd])
        guard let jsonData = slice.data(using: .utf8) else {
            throw MemoryEnhancementError.invalidResponse
        }
        return try JSONDecoder().decode(MemoryEnhancementExtractionPayload.self, from: jsonData)
    }

    private func performChat(
        system: String,
        user: String,
        maxTokens: Int,
        temperature: Double,
        promptChars: Int
    ) async throws -> String {
        let startedAt = Date()
        let result = try await AIProxyService.shared.chatCompletion(
            model: "gpt-5-mini",
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            temperature: temperature,
            maxTokens: maxTokens,
            jsonMode: true
        )
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .openAI,
                operation: .openAIChat,
                model: "gpt-5-mini",
                statusCode: 200,
                success: true,
                durationMs: Date().timeIntervalSince(startedAt) * 1000,
                promptCharacters: promptChars,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens,
                inputImageCount: 0,
                outputImageCount: 0,
                uploadedBytes: 0
            )
        )
        return result.text
    }

}
