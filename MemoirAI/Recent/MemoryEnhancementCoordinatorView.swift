import SwiftUI
import CoreData
import Mixpanel

/// Entry for the Enhance flow: intro → guided voice (or manual) → existing character editor for review/save.
struct MemoryEnhancementCoordinatorView: View {
    private enum Route {
        case intro
        case guided
        case manual
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

    var body: some View {
        Group {
            switch route {
            case .intro:
                MemoryEnhancementIntroView(
                    onStartVoice: {
                        route = .guided
                    },
                    onEditManually: {
                        route = .manual
                    },
                    onClose: { dismiss() },
                    voiceGuideAvailable: voiceAvailable
                )
            case .guided:
                if let service = MemoryEnhancementService.fromMainBundle() {
                    MemoryEnhancementGuidedSessionView(
                        memory: memory,
                        service: service,
                        onComplete: { details in
                            preFilledDetails = details
                            route = .success
                        },
                        onBack: { route = .intro },
                        onPartialSave: { details in
                            persistExtractedCharacterDetails(
                                details,
                                memory: memory,
                                context: context,
                                profile: profileVM.selectedProfile,
                                mergeWithExisting: true
                            )
                        }
                    )
                } else {
                    Color(red: 0.98, green: 0.96, blue: 0.90)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 16) {
                                Text("Guided enhancement isn’t available.")
                                    .font(.headline)
                                Button("Back") { route = .intro }
                            }
                        }
                }
            case .manual:
                CharacterDetailsQuestionView(
                    memory: memory,
                    initialCharacterDetails: preFilledDetails,
                    onBackInsteadOfDismiss: preFilledDetails == nil ? { route = .intro } : nil
                )
                .environmentObject(profileVM)
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
                    Color(red: 0.98, green: 0.96, blue: 0.90)
                        .ignoresSafeArea()
                        .onAppear { dismiss() }
                }
            }
        }
        .onAppear {
            Mixpanel.mainInstance().track(event: "Memory Enhancement Flow Opened", properties: [
                "voice_available": voiceAvailable,
                "memory_id": memory.id?.uuidString ?? ""
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

    private var header: Color { Color(red: 0.07, green: 0.21, blue: 0.13) }
    private var terracotta: Color { Color(red: 0.82, green: 0.45, blue: 0.32) }
    private var cream: Color { Color(red: 0.98, green: 0.96, blue: 0.90) }

    private var characterCount: Int {
        characterDetails.characters.count
    }

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(terracotta.opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(terracotta)
                }

                Text("Enhanced")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(header)

                if characterCount == 0 {
                    Text("We saved your answers. You can add people to this memory anytime from the memory screen.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text(
                        characterCount == 1
                            ? "1 character was added from your voice answers. Tap Characters on the memory to edit anytime."
                            : "\(characterCount) characters were added from your voice answers. Tap Characters on the memory to edit anytime."
                    )
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
        }
        .onAppear {
            guard !didRunSave else { return }
            didRunSave = true
            persistExtractedCharacterDetails(
                characterDetails,
                memory: memory,
                context: context,
                profile: profileVM.selectedProfile,
                mergeWithExisting: false
            )
            Mixpanel.mainInstance().track(event: "Memory Enhancement Auto Saved", properties: [
                "memory_id": memory.id?.uuidString ?? "",
                "characters_saved": characterCount
            ])
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
) {
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
            let globalId = GlobalCharacterManager.shared.findOrCreateGlobalCharacter(
                name: character.name,
                profileID: profileID
            )
            details.characters[index].globalCharacterId = globalId
        }
    }

    do {
        if let encoded = try? JSONEncoder().encode(details),
           let jsonString = String(data: encoded, encoding: .utf8) {
            memory.setValue(jsonString, forKey: "characterDetails")
        }

        if let encoded = try? JSONEncoder().encode(details),
           let jsonString = String(data: encoded, encoding: .utf8) {
            UserDefaults.standard.set(jsonString, forKey: "characterDetails_\(memory.id?.uuidString ?? "unknown")")
        }

        try context.save()
        context.refresh(memory, mergeChanges: true)
        NotificationCenter.default.post(name: .memorySaved, object: nil)
        FirestoreSyncService.shared.queueMemorySyncWithProfile(memory, profile: profile)
    } catch {
        print("Memory enhancement auto-save failed: \(error)")
    }
}
