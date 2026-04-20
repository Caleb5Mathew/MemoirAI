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

// MARK: - LLM extraction payload (shared with MemoryEnhancementService + tests)

struct MemoryEnhancementExtractedCharacter: Codable, Equatable {
    var name: String
    var age: String?
    var gender: String?
    var ethnicity: String?
    var hairAndFeatures: String?
    var clothes: String?
    var relationshipToNarrator: String?
}

struct MemoryEnhancementExtractionPayload: Codable, Equatable {
    var characters: [MemoryEnhancementExtractedCharacter]
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
