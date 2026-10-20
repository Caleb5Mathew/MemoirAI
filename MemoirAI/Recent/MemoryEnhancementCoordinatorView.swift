import SwiftUI
import CoreData
import Mixpanel

/// Entry for the Enhance flow: intro → guided voice or guided typing → auto-saved success screen.
/// Voice and typing share `MemoryEnhancementGuidedSessionViewModel`, so both paths run the same
/// preflight, tiered Q&A, and structured extraction logic — they only differ in how the user
/// supplies each turn's answer.
struct MemoryEnhancementCoordinatorView: View {
    private enum Route {
        case intro
        case guided
        case guidedTyping
        case success
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var profileVM: ProfileViewModel

    let memory: MemoryEntry

    @State private var route: Route = .intro
    @State private var preFilledDetails: CharacterDetails?

    private var voiceAvailable: Bool {
        MemoryEnhancementService.fromMainBundle() != nil
    }

    /// The interview must not re-ask what the profile already knows about the narrator.
    private var narratorFacts: NarratorProfileFacts {
        NarratorProfileFacts.from(profile: profileVM.selectedProfile)
    }

    var body: some View {
        Group {
            switch route {
            case .intro:
                MemoryEnhancementIntroView(
                    onStartVoice: {
                        route = .guided
                    },
                    onEnhanceByTyping: {
                        route = .guidedTyping
                    },
                    onClose: { dismiss() },
                    voiceGuideAvailable: voiceAvailable
                )
            case .guided:
                if let service = MemoryEnhancementService.fromMainBundle(narratorFacts: narratorFacts) {
                    MemoryEnhancementGuidedSessionView(
                        memory: memory,
                        service: service,
                        profileDisplayName: profileVM.selectedProfile.name,
                        transcriptionGlossary: CloudTranscriptionService.glossary(for: profileVM.selectedProfile),
                        relationshipStyleProfileName: CharacterDetails.isRelationshipStyleProfileName(
                            profileVM.selectedProfile.name
                        ),
                        onComplete: { details in
                            preFilledDetails = details
                            route = .success
                        },
                        onBack: { route = .intro },
                        onPartialSave: { details in
                            do {
                                try persistExtractedCharacterDetails(
                                    details,
                                    memory: memory,
                                    context: context,
                                    profile: profileVM.selectedProfile,
                                    mergeWithExisting: true
                                )
                            } catch {
                                ProductAnalytics.shared.track("Memory Enhancement Save Failed", ["failure_stage": "local_save"])
                                throw error
                            }
                        }
                    )
                } else {
                    LinenTheme.paper
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 16) {
                                Text("Guided enhancement isn’t available.")
                                    .font(LinenTheme.body(16, weight: .semibold))
                                Button("Back") { route = .intro }
                            }
                        }
                }
            case .guidedTyping:
                if let service = MemoryEnhancementService.fromMainBundle(narratorFacts: narratorFacts) {
                    MemoryEnhancementGuidedTypingSessionView(
                        memory: memory,
                        service: service,
                        profileDisplayName: profileVM.selectedProfile.name,
                        relationshipStyleProfileName: CharacterDetails.isRelationshipStyleProfileName(
                            profileVM.selectedProfile.name
                        ),
                        onComplete: { details in
                            preFilledDetails = details
                            route = .success
                        },
                        onBack: { route = .intro },
                        onPartialSave: { details in
                            do {
                                try persistExtractedCharacterDetails(
                                    details,
                                    memory: memory,
                                    context: context,
                                    profile: profileVM.selectedProfile,
                                    mergeWithExisting: true
                                )
                            } catch {
                                ProductAnalytics.shared.track("Memory Enhancement Save Failed", ["failure_stage": "local_save"])
                                throw error
                            }
                        }
                    )
                } else {
                    LinenTheme.paper
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 16) {
                                Text("Guided enhancement isn’t available.")
                                    .font(LinenTheme.body(16, weight: .semibold))
                                Button("Back") { route = .intro }
                            }
                        }
                }
            case .success:
                if let details = preFilledDetails {
                    MemoryEnhancementAutoSaveSuccessView(
                        memory: memory,
                        characterDetails: details,
                        onFinished: { dismiss() }
                    )
                    .environmentObject(profileVM)
                    .environment(\.managedObjectContext, context)
                } else {
                    LinenTheme.paper
                        .ignoresSafeArea()
                        .onAppear { dismiss() }
                }
            }
        }
        .onAppear {
            ProductAnalytics.shared.track("Memory Enhancement Flow Opened", [
                    "voice_available": voiceAvailable
                ])
        }
    }
}

// MARK: - Guided completion: auto-save + success

private struct MemoryEnhancementAutoSaveSuccessView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var profileVM: ProfileViewModel

    let memory: MemoryEntry
    let characterDetails: CharacterDetails
    let onFinished: () -> Void

    @State private var didRunSave = false
    @State private var saveFailed = false

    private var header: Color { LinenTheme.ink }
    private var terracotta: Color { LinenTheme.accent }
    private var cream: Color { LinenTheme.paper }

    private var characterCount: Int {
        characterDetails.characters.count
    }

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(terracotta.opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: saveFailed ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .font(LinenTheme.body(56))
                        .foregroundStyle(terracotta)
                }

                Text(saveFailed ? "Couldn’t save yet" : "Enhanced")
                    .font(LinenTheme.heading(25))
                    .foregroundStyle(header)

                if saveFailed {
                    Text("Your changes haven’t been saved. Please try again.")
                        .font(LinenTheme.body(16, weight: .medium))
                        .foregroundStyle(LinenTheme.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again", action: save)
                        .buttonStyle(.borderedProminent)
                        .tint(terracotta)
                } else if characterCount == 0 {
                    Text("We saved your answers. You can add people to this memory anytime from the memory screen.")
                        .font(LinenTheme.body(16, weight: .medium))
                        .foregroundStyle(LinenTheme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text(
                        characterCount == 1
                            ? "1 character was added from your answers. Tap Characters on the memory to edit anytime."
                            : "\(characterCount) characters were added from your answers. Tap Characters on the memory to edit anytime."
                    )
                    .font(LinenTheme.body(16, weight: .medium))
                    .foregroundStyle(LinenTheme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
        }
        .onAppear {
            guard !didRunSave else { return }
            didRunSave = true
            save()
        }
    }

    private func save() {
        saveFailed = !MemoryEnhancementSaveOperation.perform(characterCount: characterCount, memoryID: memory.id, analytics: .shared) {
            try persistExtractedCharacterDetails(
                characterDetails,
                memory: memory,
                context: context,
                profile: profileVM.selectedProfile,
                mergeWithExisting: false
            )
        }
        if !saveFailed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onFinished()
            }
        }
    }
}

/// Mirrors `CharacterDetailsQuestionView.saveDetails()` so guided completion skips the editor.
@MainActor
private func persistExtractedCharacterDetails(
    _ incoming: CharacterDetails,
    memory: MemoryEntry,
    context: NSManagedObjectContext,
    profile: Profile,
    mergeWithExisting: Bool
) throws {
    let merged: CharacterDetails
    if mergeWithExisting {
        let existing = memory.parsedCharacterDetails ?? CharacterDetails()
        merged = CharacterDetails.merging(existing: existing, incoming: incoming)
    } else {
        merged = incoming
    }
    var details = merged
    let profileID = profile.id

    for index in details.characters.indices {
        let character = details.characters[index]
        if !character.name.isEmpty && character.globalCharacterId == nil {
            guard let globalId = GlobalCharacterManager.shared.findOrCreateGlobalCharacter(
                name: character.name,
                profileID: profileID
            ) else { continue }
            details.characters[index].globalCharacterId = globalId
        }
    }

    let encoded = try JSONEncoder().encode(details)
    let jsonString = String(decoding: encoded, as: UTF8.self)
    let previousDetails = memory.value(forKey: "characterDetails")
    memory.setValue(jsonString, forKey: "characterDetails")
    do {
        try context.save()
    } catch {
        memory.setValue(previousDetails, forKey: "characterDetails")
        throw error
    }
    if let memoryID = memory.id {
        UserDefaults.standard.set(jsonString, forKey: "characterDetails_\(memoryID.uuidString)")
    }
    context.refresh(memory, mergeChanges: true)
    NotificationCenter.default.post(name: .memorySaved, object: nil)
    FirestoreSyncService.shared.queueMemorySyncWithProfile(memory, profile: profile)
}

@MainActor
enum MemoryEnhancementSaveOperation {
    static func perform(
        characterCount: Int,
        memoryID: UUID? = nil,
        analytics: ProductAnalytics,
        persist: () throws -> Void
    ) -> Bool {
        do {
            try persist()
            if let memoryID {
                EnhancementSessionDraft.clear(memoryId: memoryID)
            }
            analytics.track("Memory Enhancement Auto Saved", ["characters_saved": characterCount])
            return true
        } catch {
            analytics.track("Memory Enhancement Save Failed", ["failure_stage": "local_save"])
            return false
        }
    }
}
