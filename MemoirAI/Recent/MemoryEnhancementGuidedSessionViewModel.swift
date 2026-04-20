import Foundation
import CoreData
import Mixpanel

@MainActor
final class MemoryEnhancementGuidedSessionViewModel: ObservableObject {
    @Published var currentQuestion: String
    @Published var turns: [MemoryEnhancementTurn] = []
    @Published var isAnalyzing = false
    @Published var isBootstrapping = false
    @Published var errorMessage: String?
    /// When set, guided flow should transition to review/save.
    @Published var extractionResult: CharacterDetails?

    private let memoryText: String
    private let memoryTitle: String?
    private let memoryId: UUID?
    private let service: MemoryEnhancementService
    private let onFinished: (CharacterDetails) -> Void
    private let onPartialSave: ((CharacterDetails) async -> Void)?
    private var didFinishExtraction = false
    /// After a successful partial persist, skip duplicate saves until `turns.count` changes.
    private var lastPartialSavedTurnCount: Int = -1
    /// True when state was loaded from `EnhancementSessionDraft` (skip first-question bootstrap).
    private let loadedFromDraft: Bool

    init(
        memory: MemoryEntry,
        service: MemoryEnhancementService,
        onFinished: @escaping (CharacterDetails) -> Void,
        onPartialSave: ((CharacterDetails) async -> Void)? = nil
    ) {
        self.memoryText = (memory.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.memoryTitle = memory.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.memoryId = memory.id
        self.service = service
        self.onFinished = onFinished
        self.onPartialSave = onPartialSave

        if let id = memory.id, let draft = EnhancementSessionDraft.load(memoryId: id) {
            self.turns = draft.turns
            self.currentQuestion = draft.currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            self.loadedFromDraft = true
        } else {
            self.currentQuestion = ""
            self.loadedFromDraft = false
        }
    }

    /// Loads the first tailored question or repairs an inconsistent draft (e.g. missing `currentQuestion`).
    func bootstrapIfNeeded() async {
        if loadedFromDraft {
            if currentQuestion.isEmpty, !turns.isEmpty {
                await recoverNextQuestionAfterIncompleteDraft()
            }
            return
        }
        guard currentQuestion.isEmpty else { return }
        await loadFirstQuestion()
    }

    /// True after a full guided completion (extract + success flow), not after partial saves.
    var hasCompletedFullSession: Bool { didFinishExtraction }

    /// Persists character cards from current Q&A without ending the session (merge with existing on memory).
    func persistPartialProgress() async {
        guard !didFinishExtraction else { return }
        guard !turns.isEmpty else { return }
        guard let onPartialSave else { return }
        guard turns.count != lastPartialSavedTurnCount else { return }

        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            let details = try await extractDetails()
            lastPartialSavedTurnCount = turns.count
            await onPartialSave(details)
        } catch {
            print("MemoryEnhancementGuidedSessionViewModel persistPartialProgress: \(error)")
        }
    }

    func persistDraft() {
        guard let memoryId else { return }
        guard !currentQuestion.isEmpty || !turns.isEmpty else { return }
        EnhancementSessionDraft(turns: turns, currentQuestion: currentQuestion).save(memoryId: memoryId)
    }

    /// Append a transcribed/typed answer and advance the interview state machine.
    func submitAnswer(_ answer: String) async {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "We didn’t catch enough speech—try recording again."
            return
        }
        turns.append(MemoryEnhancementTurn(question: currentQuestion, answer: trimmed))

        if turns.count >= MemoryEnhancementSessionRules.maxSessionTurns {
            isAnalyzing = true
            errorMessage = nil
            defer { isAnalyzing = false }
            do {
                try await runExtraction()
            } catch {
                errorMessage = "Couldn’t build character details. Try again."
                print("MemoryEnhancementGuidedSessionViewModel cap extraction: \(error)")
            }
            return
        }

        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        do {
            let analysis = try await service.analyzeTurn(
                memoryText: memoryText,
                turns: turns
            )
            let action = MemoryEnhancementSessionRules.resolveNextAction(
                analysis: analysis,
                totalTurnsCompleted: turns.count
            )
            switch action {
            case .askNext(let q):
                currentQuestion = q
                persistDraft()
            case .extract:
                try await runExtraction()
            }
        } catch {
            errorMessage = "We couldn’t update the next question. Check your connection and try again."
            print("MemoryEnhancementGuidedSessionViewModel submitAnswer: \(error)")
        }
    }

    /// Skip empty answers — still moves forward conservatively by asking the model to advance.
    func skipCurrentQuestion() async {
        await submitAnswer("I’d rather not say / I don’t remember.")
    }

    /// End early and extract from whatever was captured.
    func finishNow() async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            try await runExtraction()
        } catch {
            errorMessage = "Couldn’t build character details. Try again."
            print("finishNow extraction: \(error)")
        }
    }

    private func loadFirstQuestion() async {
        isBootstrapping = true
        errorMessage = nil
        defer { isBootstrapping = false }
        do {
            let q = try await service.generateFirstQuestion(
                memoryTitle: memoryTitle,
                memoryText: memoryText
            )
            currentQuestion = q
            persistDraft()
        } catch {
            errorMessage = "We couldn’t prepare your first question. Check your connection and try again."
            currentQuestion = "Who was there with you in this memory?"
            persistDraft()
            print("loadFirstQuestion: \(error)")
        }
    }

    private func recoverNextQuestionAfterIncompleteDraft() async {
        isBootstrapping = true
        errorMessage = nil
        defer { isBootstrapping = false }
        do {
            if turns.count >= MemoryEnhancementSessionRules.maxSessionTurns {
                try await runExtraction()
                return
            }
            let analysis = try await service.analyzeTurn(
                memoryText: memoryText,
                turns: turns
            )
            let action = MemoryEnhancementSessionRules.resolveNextAction(
                analysis: analysis,
                totalTurnsCompleted: turns.count
            )
            switch action {
            case .askNext(let q):
                currentQuestion = q
                persistDraft()
            case .extract:
                try await runExtraction()
            }
        } catch {
            errorMessage = "Couldn’t resume your session. Try again."
            currentQuestion = "Where were you when this happened?"
            persistDraft()
            print("recoverNextQuestionAfterIncompleteDraft: \(error)")
        }
    }

    private func extractDetails() async throws -> CharacterDetails {
        try await service.extractStructuredDetails(
            memoryText: memoryText,
            turns: turns
        )
    }

    private func runExtraction() async throws {
        guard !didFinishExtraction else { return }
        let details = try await extractDetails()
        didFinishExtraction = true
        extractionResult = details
        if let memoryId {
            EnhancementSessionDraft.clear(memoryId: memoryId)
        }
        Mixpanel.mainInstance().track(event: "Memory Enhancement Guided Complete", properties: [
            "turns": turns.count,
            "characters_extracted": details.characters.count,
            "memory_id": memoryId?.uuidString ?? ""
        ])
        onFinished(details)
    }
}
