import Foundation

/// OpenAI-backed analysis + extraction for guided memory enhancement.
actor MemoryEnhancementService {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    static func fromMainBundle() -> MemoryEnhancementService? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return MemoryEnhancementService(apiKey: key)
    }

    /// First interview question tailored to gaps in the memory (people, scene, visuals).
    func generateFirstQuestion(memoryTitle: String?, memoryText: String) async throws -> String {
        let title = (memoryTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = """
        Goal: fill **illustration gaps** for one memory—drawable people first, then a **simple** sense of place. Read the memory and adapt: only ask for what is **not** already there.

        **Order (important):**
        1) **Character details first (main phase):** For each key person in the scene, gather what’s missing for drawing. **Ethnicity / cultural background, hair, and clothing** help a lot—**you may ask for several of these together in one natural, open-ended question** (one sentence) instead of splitting into tiny separate questions. Keep it respectful; include ethnicity when it would help depict someone and isn’t already in the text. Stay general (outfit vibe, hair length/color/style)—not every accessory.
        2) **If someone is only referred to vaguely** (“my girlfriend,” “a friend”) **and** you need a name first, use **one short question that is only** the name or what they called them—then use a bundled character question next for look/background/clothes.
        3) **Scene second:** Only after the main people have a drawable pass (or the text already describes them well), ask **one** question about **general** setting—where or what kind of place (broad strokes). Do not mix a full scene description request into the same question as a heavy character bundle unless the memory is very short.

        Do **not** ask: how people met, relationship history, plot, why things happened, mood monologues, tiny props, or exact lighting.

        One question per turn, open-ended, warm. Character bundles: aim under ~30 words. Name-only questions: under ~15 words. No yes/no.

        If the text is empty, ask for one concrete moment tied to the title.
        Return ONLY valid JSON: {"first_question":"..."}
        """
        let user = """
        Memory title:
        \(title.isEmpty ? "(none)" : title)

        Memory text:
        \(body.isEmpty ? "(empty — user may only have a title or fragment)" : body.prefix(2500))
        """
        struct FirstQ: Codable { var first_question: String }
        let dto: FirstQ = try await postJSONDecoding(system: system, user: user)
        let q = dto.first_question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw MemoryEnhancementError.invalidResponse }
        return q
    }

    func analyzeTurn(
        memoryText: String,
        turns: [MemoryEnhancementTurn]
    ) async throws -> MemoryEnhancementTurnAnalysis {
        let qa = turns.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        let answered = turns.count
        let system = """
        Goal: **character details first**, then **general scene**. Re-read the memory; list who appears; ask only what is **still missing** after prior answers. Adapt each question to **this** scenario.

        **Character phase (primary):** For whoever still isn’t drawable, gather missing **ethnicity/cultural background (very helpful for illustration), hair, clothes, and rough look**. You **should often combine** those in **one** natural open-ended question per turn (single sentence)—e.g. invite them to describe background, hair, and what they wore together—rather than one tiny fact per question. Respectful; skip ethnicity if it would be intrusive or already stated.

        **Name-only exception:** If someone is vague (“my girlfriend”) and you still need a name, that turn may be **only** name / what they called them—**then** use bundled character questions.

        **Scene phase (after characters are mostly covered):** Ask for **general** setting—where or what kind of place. Broad only; no mood, lighting trivia, or small props. Prefer **not** to pack a big scene riddle into the same question as a full character bundle unless the memory is very thin.

        Forbidden: how you met, backstory, plot, why things happened, relationship history, mood essays.

        Rules:
        - One question per turn; open-ended; no yes/no. Character bundles: ~30 words max; name-only: ~15 words.
        - Use ONLY memory text + answers; don’t invent.
        - Cap: \(MemoryEnhancementSessionRules.maxSessionTurns) user answers; completed: \(answered). At cap → next_step extract.
        - Often finish in 2–3 answers if people + rough place are clear; use 4–5 only for real gaps.
        - If user doesn’t remember, move on.
        - next_question null iff extract; else non-empty.
        Return JSON: next_step ("ask_next"|"extract"), next_question (string or null), reason (string or null).
        """
        let user = """
        Original memory:
        \(memoryText.prefix(2500))

        Interview so far:
        \(qa.isEmpty ? "(none yet)" : qa)
        """
        return try await postJSON(system: system, user: user)
    }

    func extractStructuredDetails(
        memoryText: String,
        turns: [MemoryEnhancementTurn]
    ) async throws -> CharacterDetails {
        let qa = turns.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        let system = """
        From the memory and the interview Q&A, build character cards for illustration. Users may answer one bundled question with ethnicity, hair, and clothes together—split those into the right fields. Focus on people the story needs to show; do not invent fine detail.
        Rules:
        - Output ONLY JSON: {"characters":[...]}.
        - Each character: name (required string), age, gender, ethnicity (use what the user said about background, heritage, or ethnicity—"" if never mentioned), hairAndFeatures, clothes, relationshipToNarrator (strings; use "" if unknown).
        - Do NOT invent names or traits not grounded in the text or answers; leave fields empty when unknown.
        - Merge duplicates (same person).
        - If no people appear, return {"characters":[]}.
        """
        let user = """
        Memory:
        \(memoryText.prefix(2500))

        Q&A:
        \(qa.isEmpty ? "(none)" : qa)
        """
        let dto: MemoryEnhancementExtractionPayload = try await postJSONExtraction(system: system, user: user)
        return CharacterDetails.fromExtractionPayload(dto)
    }

    // MARK: - Networking

    private func postJSON(system: String, user: String) async throws -> MemoryEnhancementTurnAnalysis {
        var body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.2,
            "max_tokens": 220,
            "response_format": ["type": "json_object"]
        ]
        let data = try await performChat(body: &body, promptChars: user.count)
        struct Root: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let raw = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? ""
        guard let jsonStart = raw.firstIndex(of: "{"),
              let jsonEnd = raw.lastIndex(of: "}") else {
            throw MemoryEnhancementError.invalidResponse
        }
        let slice = String(raw[jsonStart...jsonEnd])
        guard let jsonData = slice.data(using: .utf8) else {
            throw MemoryEnhancementError.invalidResponse
        }
        return try JSONDecoder().decode(MemoryEnhancementTurnAnalysis.self, from: jsonData)
    }

    private func postJSONDecoding<T: Decodable>(system: String, user: String) async throws -> T {
        var body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.2,
            "max_tokens": 220,
            "response_format": ["type": "json_object"]
        ]
        let data = try await performChat(body: &body, promptChars: user.count)
        let raw = try MemoryEnhancementService.decodeOpenAIChatContent(from: data)
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
        var body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.15,
            "max_tokens": 1200,
            "response_format": ["type": "json_object"]
        ]
        let data = try await performChat(body: &body, promptChars: user.count)
        struct Root: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let raw = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? ""
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

    private func performChat(body: inout [String: Any], promptChars: Int) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let startedAt = Date()
        let (data, resp) = try await session.data(for: req)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode
        let usage = DevCostTelemetryService.extractOpenAIUsage(from: data)
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .openAI,
                operation: .openAIChat,
                model: "gpt-4o-mini",
                statusCode: statusCode,
                success: (200...299).contains(statusCode ?? 0),
                durationMs: Date().timeIntervalSince(startedAt) * 1000,
                promptCharacters: promptChars,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                inputImageCount: 0,
                outputImageCount: 0,
                uploadedBytes: 0
            )
        )
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MemoryEnhancementError.invalidResponse
        }
        return data
    }

    private static func decodeOpenAIChatContent(from data: Data) throws -> String {
        struct OpenAIChatRoot: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        return try JSONDecoder().decode(OpenAIChatRoot.self, from: data).choices.first?.message.content ?? ""
    }

}
