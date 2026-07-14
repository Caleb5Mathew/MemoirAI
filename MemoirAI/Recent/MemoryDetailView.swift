import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import CoreData
import Mixpanel
import Speech

// MARK: - Character Details Structure
struct CharacterDetails: Codable {
    var characters: [Character] = []
    
    struct Character: Codable, Identifiable {
        let id = UUID()
        var globalCharacterId: UUID?
        var name: String = ""
        var age: String = ""
        var gender: String = ""
        var ethnicity: String = ""
        var hairAndFeatures: String = ""
        var clothes: String = ""
        var relationshipToNarrator: String = ""
        
        // Legacy fields kept for backward compatibility with older data
        var appearance: String = ""
        var race: String = ""
        var physicalDescription: String = ""
        var clothing: String = ""
        
        var combinedAppearance: String {
            var parts: [String] = []
            if !ethnicity.isEmpty { parts.append(ethnicity) }
            if !hairAndFeatures.isEmpty { parts.append(hairAndFeatures) }
            if !clothes.isEmpty { parts.append("wearing \(clothes)") }
            return parts.isEmpty ? appearance : parts.joined(separator: ", ")
        }
        
        enum CodingKeys: String, CodingKey {
            case globalCharacterId, name, age, gender, relationshipToNarrator
            case ethnicity, hairAndFeatures, clothes
            case appearance, race, physicalDescription, clothing
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            globalCharacterId = try container.decodeIfPresent(UUID.self, forKey: .globalCharacterId)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            age = try container.decodeIfPresent(String.self, forKey: .age) ?? ""
            gender = try container.decodeIfPresent(String.self, forKey: .gender) ?? ""
            relationshipToNarrator = try container.decodeIfPresent(String.self, forKey: .relationshipToNarrator) ?? ""
            
            // Always decode legacy values so mixed-format records can still backfill
            // missing stable traits even when some new split fields exist.
            let oldAppearance = try container.decodeIfPresent(String.self, forKey: .appearance) ?? ""
            let oldRace = try container.decodeIfPresent(String.self, forKey: .race) ?? ""
            let oldPhysical = try container.decodeIfPresent(String.self, forKey: .physicalDescription) ?? ""
            let oldClothing = try container.decodeIfPresent(String.self, forKey: .clothing) ?? ""
            
            // Try new split fields first
            let decodedEthnicity = try container.decodeIfPresent(String.self, forKey: .ethnicity) ?? ""
            let decodedHair = try container.decodeIfPresent(String.self, forKey: .hairAndFeatures) ?? ""
            let decodedClothes = try container.decodeIfPresent(String.self, forKey: .clothes) ?? ""
            
            let hasNewFields = !decodedEthnicity.isEmpty || !decodedHair.isEmpty || !decodedClothes.isEmpty
            
            if hasNewFields {
                // Per-field fallback from legacy keeps partial mixed records usable.
                ethnicity = decodedEthnicity.isEmpty ? oldRace : decodedEthnicity
                if decodedHair.isEmpty {
                    hairAndFeatures = oldPhysical.isEmpty ? oldAppearance : oldPhysical
                } else {
                    hairAndFeatures = decodedHair
                }
                clothes = decodedClothes.isEmpty ? oldClothing : decodedClothes
                appearance = oldAppearance
                race = oldRace
                physicalDescription = oldPhysical
                clothing = oldClothing
            } else {
                if !oldRace.isEmpty || !oldPhysical.isEmpty || !oldClothing.isEmpty {
                    // Migrate legacy triple fields
                    ethnicity = oldRace
                    hairAndFeatures = oldPhysical
                    clothes = oldClothing
                } else if !oldAppearance.isEmpty {
                    // Single appearance blob — put into hairAndFeatures as best guess
                    hairAndFeatures = oldAppearance
                }
                
                appearance = oldAppearance
                race = oldRace
                physicalDescription = oldPhysical
                clothing = oldClothing
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encodeIfPresent(globalCharacterId, forKey: .globalCharacterId)
            try container.encode(name, forKey: .name)
            try container.encode(age, forKey: .age)
            try container.encode(gender, forKey: .gender)
            try container.encode(relationshipToNarrator, forKey: .relationshipToNarrator)
            
            // New split fields
            try container.encode(ethnicity, forKey: .ethnicity)
            try container.encode(hairAndFeatures, forKey: .hairAndFeatures)
            try container.encode(clothes, forKey: .clothes)
            
            // Backward compat: write combined appearance for older versions
            try container.encode(combinedAppearance, forKey: .appearance)
            try container.encode(ethnicity, forKey: .race)
            try container.encode(hairAndFeatures, forKey: .physicalDescription)
            try container.encode(clothes, forKey: .clothing)
        }
        
        init() {
            self.globalCharacterId = nil
            self.name = ""
            self.age = ""
            self.gender = ""
            self.ethnicity = ""
            self.hairAndFeatures = ""
            self.clothes = ""
            self.relationshipToNarrator = ""
            self.appearance = ""
            self.race = ""
            self.physicalDescription = ""
            self.clothing = ""
        }
    }
}

// MARK: - Memory Completion Checker
class MemoryCompletionChecker {
    static let shared = MemoryCompletionChecker()
    
    private init() {}
    
    /// Determines if a memory needs character details for better image generation
    func isMemoryIncomplete(_ memory: MemoryEntry) -> Bool {
        // Only check memories that have substantial text content
        guard let text = memory.text, !text.isEmpty, text.count > 50 else {
            return false
        }
        
        // Check if we already have character details
        if let detailsString = memory.characterDetails,
           !detailsString.isEmpty,
           let details = parseCharacterDetails(detailsString),
           !details.characters.isEmpty {
            return false
        }
        
        // Use simple heuristics to detect if the memory likely contains characters
        return containsCharacterReferences(text)
    }
    
    /// Parse character details from JSON string
    func parseCharacterDetails(_ jsonString: String) -> CharacterDetails? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CharacterDetails.self, from: data)
    }
    
    /// Simple heuristic to detect character references in text
    private func containsCharacterReferences(_ text: String) -> Bool {
        let lowercaseText = text.lowercased()
        
        let characterKeywords = [
            // Pronouns
            " he ", " she ", " him ", " her ", " his ", " hers ",
            // Relationships
            "mother", "father", "mom", "dad", "brother", "sister",
            "friend", "cousin", "aunt", "uncle", "grandma", "grandpa",
            "wife", "husband", "daughter", "son", "child", "kid",
            // Groups
            "people", "family", "friends", "neighbors", "classmates",
            // Actions that involve others
            "talked to", "met", "played with", "went with", "saw"
        ]
        
        return characterKeywords.contains { lowercaseText.contains($0) }
    }
}

// MARK: - MemoryEntry Extension
extension MemoryEntry {
    var isIncomplete: Bool {
        return MemoryCompletionChecker.shared.isMemoryIncomplete(self)
    }
    
    var parsedCharacterDetails: CharacterDetails? {
        // Try primary source first (Core Data)
        if let detailsString = self.value(forKey: "characterDetails") as? String,
           !detailsString.isEmpty {
            if let details = MemoryCompletionChecker.shared.parseCharacterDetails(detailsString) {
                print("✅ Loaded character details from Core Data")
                return details
            }
        }
        
        // Fallback to UserDefaults backup
        if let memoryId = self.id?.uuidString,
           let backupString = UserDefaults.standard.string(forKey: "characterDetails_\(memoryId)"),
           !backupString.isEmpty {
            if let details = MemoryCompletionChecker.shared.parseCharacterDetails(backupString) {
                print("✅ Loaded character details from UserDefaults backup")
                return details
            }
        }
        
        print("ℹ️ No character details found for memory")
        return nil
    }
}

struct MemoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    @StateObject private var familyManager = FamilyManager.shared
    @StateObject private var permissionManager = PermissionManager.shared
    let memory: MemoryEntry

    @State private var audioEngine = AVAudioEngine()
    @State private var playerNode = AVAudioPlayerNode()
    @State private var eqNode = AVAudioUnitEQ(numberOfBands: 1)
    @State private var isPlaying = false

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var images: [UIImage] = []

    @State private var isEditing = false
    @State private var draftText = ""
    @State private var showFamilyShareSuccess = false
    @State private var showCharacterDetails = false
    @State private var showEnhancementCoordinator = false
    @State private var animateEnhanceGlow = false
    @State private var refreshTrigger = 0
    @State private var lastTitleUpdateTime: Date? = nil
    @State private var titleUpdateTask: Task<Void, Never>? = nil

    // Batch transcription support
    @StateObject private var transcriptionManager = BatchTranscriptionManager.shared
    @State private var showTranscriptionProgress = false
    @State private var transcriptionAlertMessage = ""
    @State private var showTranscriptionAlert = false
    @State private var isTextExpanded = false
    @State private var showReRecordConfirm = false
    @State private var showReRecordSheet = false

    /// Aligned with `RecentMemoriesView` warm parchment base.
    private let backgroundColor = Color(red: 0.98, green: 0.96, blue: 0.89)
    private let cardSurface = Color.white
    /// Subtle hairline; keeps cards calm vs heavy shadows.
    private let cardStroke = Color.black.opacity(0.06)
    private let headerColor = Color(red: 0.12, green: 0.22, blue: 0.18)
    private let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.5)
    private let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    
    // Check if memory should show Enhance button
    private var shouldShowEnhanceButton: Bool {
        let hasText = memory.text != nil && !(memory.text?.isEmpty ?? true)
        let hasCharacterDetails = memory.parsedCharacterDetails?.characters.isEmpty == false
        return hasText && !hasCharacterDetails && !isEditing
    }

    // MARK: - Layout (warm memoir surface)

    private var memoryDetailTitle: some View {
        Text(memory.prompt ?? "Memory")
            .font(.system(size: 28, weight: .semibold, design: .serif))
            .foregroundColor(headerColor)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.top, 4)
    }

    private var memoryPrimaryCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let date = memory.createdAt {
                memoryDateRow(date: date)
            }

            memoryVoiceSection

            if isEditing {
                memoryEditBlock
            } else if let saved = memory.text, !saved.isEmpty {
                memoryReadTextBlock(saved)
            } else if memory.hasAudio {
                memoryTranscriptionStatusBlock
            }

            if shouldShowEnhanceButton {
                characterEnhancementSection
            } else if let details = memory.parsedCharacterDetails, !details.characters.isEmpty {
                characterDetailsSection(details: details)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func memoryDateRow(date: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(terracotta)
            Text(dateFormatted(date))
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundColor(headerColor.opacity(0.88))
            Spacer()
        }
    }

    /// Play / pause + replace recording (memoir-themed confirm before clear).
    /// Only shown when the memory actually has a voice recording.
    @ViewBuilder
    private var memoryVoiceSection: some View {
        if let url = memory.playbackURL {
            memoryAudioRow(url: url)
        }
    }

    @ViewBuilder
    private func memoryAudioRow(url: URL) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: { togglePlayback(url: url) }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(terracotta.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(terracotta)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recording")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(textSecondary)
                        Text(isPlaying ? "Playing…" : "Tap to play this memory")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundColor(headerColor)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(softCream.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: { showReRecordConfirm = true }) {
                VStack(spacing: 4) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Re-record")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(terracotta)
                .frame(width: 72)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Replace voice recording")
        }
    }

    private var reRecordConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showReRecordConfirm = false }

            VStack(spacing: 18) {
                Text("Replace this recording?")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundColor(headerColor)
                    .multilineTextAlignment(.center)

                Text("This will permanently clear the current voice recording. You can then record a new one.")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    Button(action: confirmClearAudioAndOpenRecorder) {
                        Text("Clear and Re-record")
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(terracotta)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: { showReRecordConfirm = false }) {
                        Text("Keep Recording")
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundColor(headerColor.opacity(0.88))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(red: 0.96, green: 0.94, blue: 0.88))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(26)
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 10)
            .padding(.horizontal, 28)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: showReRecordConfirm)
    }

    @ViewBuilder
    private func memoryReadTextBlock(_ saved: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(saved)
                .font(.custom("Georgia", size: 18))
                .multilineTextAlignment(.leading)
                .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.13))
                .lineSpacing(6)
                .lineLimit(isTextExpanded ? nil : 10)
                .padding(.vertical, 2)

            if saved.count > 300 || saved.filter({ $0 == "\n" }).count > 8 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isTextExpanded.toggle()
                    }
                }) {
                    Text(isTextExpanded ? "Read less" : "Read more")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundColor(terracotta)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Shown in place of the transcript text when there is audio but no text yet
    /// — distinguishes "actively transcribing right now" from "queued for
    /// automatic retry" so the user isn't left guessing.
    @ViewBuilder
    private var memoryTranscriptionStatusBlock: some View {
        HStack(spacing: 10) {
            if isTranscribingNow {
                ProgressView()
                    .tint(terracotta)
                Text("Transcribing…")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(textSecondary)
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(terracotta.opacity(0.7))
                Text("Audio saved — transcript coming soon. We'll retry automatically.")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    /// True while this memory's audio is actively being transcribed right now.
    private var isTranscribingNow: Bool {
        guard let id = memory.id else { return false }
        return transcriptionManager.isInFlight(id)
    }

    private var memoryEditBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 13, weight: .semibold))
                Text("Editing")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(terracotta)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(terracotta.opacity(0.12))
            )

            TextEditor(text: $draftText)
                .font(.custom("Georgia", size: 18))
                .lineSpacing(5)
                .frame(minHeight: 220)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(terracotta.opacity(0.28), lineWidth: 1)
                )
                .onAppear { draftText = memory.text ?? "" }
                .onChange(of: draftText) { _ in
                    // Title regeneration happens on save (toolbar checkmark).
                }
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
            VStack(alignment: .center, spacing: 0) {
                memoryDetailTitle
                    .padding(.bottom, 20)

                memoryPrimaryCard

                if familyManager.currentFamily != nil {
                    familySharingSection
                }

                // MARK: - Photo Section (Commented Out)
                // Photos section has been disabled - uncomment below to re-enable
                /*
                VStack(spacing: 20) {
                    Text("Photos")
                        .font(.subheadline)
                        .textCase(.uppercase)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let gridWidth = UIScreen.main.bounds.width * 0.9
                    let thumbSize = (gridWidth - (3 * 8)) / 4
                    let remaining = max(0, 8 - photoDatas.count)

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(0..<8, id: \.self) { idx in
                            if idx < images.count {
                                Image(uiImage: images[idx])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: thumbSize, height: thumbSize)
                                    .clipped()
                                    .cornerRadius(8)
                            } else {
                                PhotosPicker(
                                    selection: $photoItems,
                                    maxSelectionCount: remaining,
                                    matching: .images,
                                    photoLibrary: .shared()
                                ) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(softCream)
                                            .frame(width: thumbSize, height: thumbSize)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.black, style: StrokeStyle(lineWidth: 2, dash: [5]))
                                            )
                                        Image(systemName: "plus")
                                            .font(.title)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: photoItems.map(
                        { $0.itemIdentifier ?? "" }
                    )) { _ in
                        handlePhotoItemsChange(photoItems)
                    }
                }
                .padding()
                .background(cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 6)
                .padding(.horizontal, 20)
                */

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .onAppear(perform: loadPhotosFromRelationship)
            .id(refreshTrigger)
            }

            if showReRecordConfirm {
                reRecordConfirmationOverlay
                    .zIndex(60)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(headerColor.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.85),
                                            Color.white.opacity(0.65)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .allowsHitTesting(true)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if familyManager.currentFamily != nil {
                    Button(action: shareWithFamily) {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(terracotta)
                    }
                }
                
                Button(action: {
                    let hasCards = memory.parsedCharacterDetails?.characters.isEmpty == false
                    if hasCards {
                        showCharacterDetails = true
                    } else if GuidedMemoryEnhancementFeature.isEnabled {
                        showEnhancementCoordinator = true
                    } else {
                        showCharacterDetails = true
                    }
                }) {
                    if let details = memory.parsedCharacterDetails, !details.characters.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if memory.isIncomplete {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.gray)
                    }
                }
                
                Button(action: shareMemory) {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Button(action: {
                    if isEditing {
                        // Cancel any pending title update
                        titleUpdateTask?.cancel()
                        titleUpdateTask = nil
                        
                        memory.text = draftText
                        
                        // Final title regeneration if needed (after user stops editing)
                        if !draftText.isEmpty {
                            Task {
                                await regenerateTitleIfNeededSync(for: draftText)
                            }
                        }
                        
                        do {
                            try context.save()
                            NotificationCenter.default.post(name: .memorySaved, object: nil)
                        } catch {
                            print("Failed to save edited text:", error)
                        }
                    } else {
                        draftText = memory.text ?? ""
                    }
                    isEditing.toggle()
                }) {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                }

                // TRANSCRIBE ALL BUTTON
                Button(action: handleBatchTranscription) {
                    Image(systemName: "waveform.badge.mic")
                }
                .disabled(!transcriptionManager.hasUntranscribed)
            }
        }
        .tint(terracotta)
        .alert("Shared with Family!", isPresented: $showFamilyShareSuccess) {
            Button("OK") { }
        } message: {
            Text("Your memory has been shared with \(familyManager.currentFamily?.name ?? "your family"). They can now see and react to it!")
        }
        .fullScreenCover(isPresented: $showCharacterDetails) {
            CharacterDetailsQuestionView(memory: memory)
                .environmentObject(profileVM)
        }
        .fullScreenCover(isPresented: $showEnhancementCoordinator) {
            MemoryEnhancementCoordinatorView(memory: memory)
                .environmentObject(profileVM)
        }
        .fullScreenCover(isPresented: $showReRecordSheet) {
            ReRecordAudioView(memoryObjectID: memory.objectID, promptText: memory.prompt)
                .environmentObject(profileVM)
        }
        .onAppear {
            Mixpanel.mainInstance().track(event: "Viewed Memory", properties: [
                "chapter_title": memory.chapter ?? "",
                "prompt_text": memory.prompt ?? "",
                "has_audio": memory.playbackURL != nil,
                "has_text": !(memory.text?.isEmpty ?? true),
                "has_photos": !(memory.photos?.allObjects.isEmpty ?? true),
                "created_at": memory.createdAt?.timeIntervalSince1970 ?? 0
            ])
            
            loadPhotosFromRelationship()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memorySaved)) { _ in
            // Refresh the UI when character details are saved
            DispatchQueue.main.async {
                refreshTrigger += 1
                context.refresh(memory, mergeChanges: true)
            }
        }

        // Progress sheet
        .sheet(isPresented: $showTranscriptionProgress) {
            VStack(spacing: 20) {
                Text("Transcribing Memories…")
                    .font(.headline)
                ProgressView(value: Double(transcriptionManager.processed), total: Double(max(transcriptionManager.total, 1)))
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .frame(width: 80, height: 80)
                Text("\(transcriptionManager.processed) / \(transcriptionManager.total)")
                    .font(.subheadline)
                    .padding(.bottom, 20)
            }
            .padding()
        }
        // Alert for already-complete or permission issues
        .alert(transcriptionAlertMessage, isPresented: $showTranscriptionAlert) {
            Button("OK", role: .cancel) {}
        }
        // Permission alerts
        .fullScreenCover(isPresented: $permissionManager.showSpeechPermissionAlert) {
            SpeechRecognitionPermissionAlert(
                isPresented: $permissionManager.showSpeechPermissionAlert,
                onSettingsTap: permissionManager.openSettings
            )
        }
    }
    
    // MARK: - Family Sharing Section
    
    private var familySharingSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Share with family")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundColor(headerColor)

                    Text("Let \(familyManager.currentFamily?.name ?? "your family") see this memory.")
                        .font(.system(size: 14))
                        .foregroundColor(textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button(action: shareWithFamily) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill")
                        Text("Share")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(terracotta)
                    )
                }
                .buttonStyle(.plain)
            }

            if !familyManager.familyMembers.isEmpty {
                HStack(spacing: 10) {
                    Text("Family")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(textSecondary)

                    ForEach(familyManager.familyMembers.prefix(4)) { member in
                        Circle()
                            .fill(terracotta.opacity(0.22))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(member.name.prefix(1)).uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(headerColor)
                            )
                    }

                    if familyManager.familyMembers.count > 4 {
                        Text("+\(familyManager.familyMembers.count - 4)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(textSecondary)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .background(cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Family Sharing Functions
    
    private func shareWithFamily() {
        guard let familyId = familyManager.currentFamily?.id else { return }
        
        let alreadyShared = familyManager.sharedStories.contains { story in
            story.memoryEntryId == memory.id && story.familyGroupId == familyId
        }
        
        if alreadyShared {
            return
        }
        
        familyManager.shareStory(memory, with: familyId)
        showFamilyShareSuccess = true
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    // MARK: - Existing Functions

    // MARK: - Photo Functions (Commented Out)
    // Photo handling functions have been disabled - uncomment below to re-enable
    /*
    private func handlePhotoItemsChange(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoDatas.append(data)
                    if let ui = UIImage(data: data) {
                        images.append(ui)
                    }
                    let photo = Photo(context: context)
                    photo.id = UUID()
                    photo.data = data
                    photo.memoryEntry = memory
                }
            }
            try? context.save()
            photoItems.removeAll()
        }
    }

    private func loadPhotosFromRelationship() {
        photoDatas.removeAll()
        images.removeAll()
        guard let photoSet = memory.photos as? Set<Photo> else { return }
        let sorted = photoSet.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        for photo in sorted {
            if let data = photo.data, let ui = UIImage(data: data) {
                photoDatas.append(data)
                images.append(ui)
            }
        }
    }
    */
    
    // Stub functions to prevent compile errors
    private func handlePhotoItemsChange(_ items: [PhotosPickerItem]) {
        // Photo adding disabled
    }
    
    private func loadPhotosFromRelationship() {
        // Photo loading disabled
    }

    private func stopPlaybackIfNeeded() {
        if isPlaying {
            playerNode.stop()
            audioEngine.stop()
            isPlaying = false
        }
    }

    private func deleteAudioFileOnDiskIfPresent() {
        guard let urlString = memory.audioFileURL,
              let url = URL(string: urlString),
              url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func confirmClearAudioAndOpenRecorder() {
        showReRecordConfirm = false
        stopPlaybackIfNeeded()
        deleteAudioFileOnDiskIfPresent()
        memory.audioData = nil
        memory.audioFileURL = nil
        do {
            try context.save()
            FirestoreSyncService.shared.queueMemorySyncWithProfile(memory, profile: profileVM.selectedProfile)
            NotificationCenter.default.post(name: .memorySaved, object: nil)
            refreshTrigger += 1
        } catch {
            print("Failed to clear audio for re-record: \(error)")
        }
        showReRecordSheet = true
    }

    private func togglePlayback(url: URL) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.overrideOutputAudioPort(.speaker)
            if isPlaying {
                playerNode.stop()
                audioEngine.stop()
                isPlaying = false
            } else {
                eqNode.globalGain = +22
                if !audioEngine.attachedNodes.contains(playerNode) {
                    audioEngine.attach(playerNode)
                    audioEngine.attach(eqNode)
                    audioEngine.connect(playerNode, to: eqNode, format: nil)
                    audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: nil)
                }
                let file = try AVAudioFile(forReading: url)
                try audioEngine.start()
                playerNode.scheduleFile(file, at: nil)
                playerNode.play()
                isPlaying = true
            }
        } catch {
            print("Engine playback error: \(error)")
        }
    }

    private func shareMemory() {
        var items: [Any] = []
        if let text = memory.text { items.append(text) }
        if let url = memory.playbackURL {
            items.append(url)
        }
        items.append(contentsOf: images)
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = av.popoverPresentationController,
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private func dateFormatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        return fmt.string(from: date)
    }
    
    // MARK: - Character Details Sections
    
    private var characterEnhancementSection: some View {
        Button(action: {
            if GuidedMemoryEnhancementFeature.isEnabled {
                showEnhancementCoordinator = true
            } else {
                showCharacterDetails = true
            }
        }) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(terracotta)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(softCream.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(terracotta.opacity(0.15), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enhance for better images")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundColor(headerColor)

                    Text("Add character details so story art matches your memory.")
                        .font(.system(size: 13))
                        .foregroundColor(textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(terracotta.opacity(0.5))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(softCream.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        Color.orange,
                                        Color.yellow,
                                        Color.red.opacity(0.8),
                                        Color.orange
                                    ]),
                                    center: .center,
                                    angle: .degrees(animateEnhanceGlow ? 360 : 0)
                                ),
                                lineWidth: 3
                            )
                    )
            )
            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                animateEnhanceGlow = true
            }
        }
    }
    
    private func characterDetailsSection(details: CharacterDetails) -> some View {
        Button(action: { showCharacterDetails = true }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(red: 0.35, green: 0.62, blue: 0.42))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Character details")
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundColor(headerColor)
                        Text("\(details.characters.count) character\(details.characters.count == 1 ? "" : "s") saved")
                            .font(.system(size: 13))
                            .foregroundColor(textSecondary)
                    }

                    Spacer(minLength: 8)

                    Text("Edit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(terracotta)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(details.characters.prefix(4)) { character in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(terracotta.opacity(0.14))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Text(character.name.isEmpty ? "?" : String(character.name.prefix(1).uppercased()))
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(headerColor)
                                    )

                                Text(character.name.isEmpty ? "Unnamed" : character.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(headerColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(softCream.opacity(0.65))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(cardStroke, lineWidth: 1)
                            )
                        }

                        if details.characters.count > 4 {
                            Text("+\(details.characters.count - 4)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.04))
                                )
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(softCream.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Title Regeneration with Rate Limiting
    private func regenerateTitleIfNeeded(for text: String) {
        // Cancel any existing pending task
        titleUpdateTask?.cancel()
        
        // Check rate limit: only update if at least 1 second has passed since last update
        let now = Date()
        if let lastUpdate = lastTitleUpdateTime,
           now.timeIntervalSince(lastUpdate) < 1.0 {
            // Schedule update for when rate limit expires
            let delay = 1.0 - now.timeIntervalSince(lastUpdate)
            titleUpdateTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !Task.isCancelled {
                    await regenerateTitleIfNeededSync(for: text)
                }
            }
            return
        }
        
        // Update immediately if rate limit allows
        titleUpdateTask = Task {
            await regenerateTitleIfNeededSync(for: text)
        }
    }
    
    private func regenerateTitleIfNeededSync(for text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let titleService = MemoryTitleService()
        if let generatedTitle = await titleService.generateTitle(from: text) {
            await MainActor.run {
                memory.prompt = generatedTitle
                lastTitleUpdateTime = Date()
                
                do {
                    try context.save()
                    NotificationCenter.default.post(name: .memorySaved, object: nil)
                    print("✅ Title regenerated: '\(generatedTitle)'")
                } catch {
                    print("❌ Failed to save regenerated title: \(error)")
                }
            }
        }
    }
    
    // MARK: - Batch Transcription Handler
    private func handleBatchTranscription() {
        // Use the new permission manager
        if permissionManager.isSpeechRecognitionAuthorized {
            startBatchTranscription()
        } else {
            permissionManager.requestSpeechRecognitionPermission()
        }
    }

    private func startBatchTranscription() {
        guard transcriptionManager.untranscribedCount > 0 else {
            transcriptionAlertMessage = "All memories are already transcribed!"
            showTranscriptionAlert = true
            return
        }
        showTranscriptionProgress = true
        transcriptionManager.start {
            // Completed
            transcriptionAlertMessage = "Finished transcribing all memories!"
            showTranscriptionProgress = false
            showTranscriptionAlert = true
        }
    }
}

// MARK: - Character Details Question View
struct CharacterDetailsQuestionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    
    let memory: MemoryEntry
    /// When set (e.g. from guided extraction), seeds the editor instead of only Core Data / backup.
    var initialCharacterDetails: CharacterDetails? = nil
    /// If non-nil, back chevron calls this (e.g. return to intro) instead of dismissing the cover.
    var onBackInsteadOfDismiss: (() -> Void)? = nil

    @State private var characterDetails: CharacterDetails
    @State private var showingAddCharacter = false
    @State private var currentCharacterIndex = 0
    @State private var saveSuccess = false
    @State private var showFullMemory = false
    @State private var existingCharacters: [CharacterDetails.Character] = []
    @State private var showExistingCharactersPicker = false
    
    // Use design tokens for consistency
    private var backgroundColor: Color { Tokens.bgPrimary }
    private var accentColor: Color { Color(red: 0.88, green: 0.52, blue: 0.28) } // Terracotta
    private var headerColor: Color { Color(red: 0.07, green: 0.21, blue: 0.13) } // Deep green
    private var softGreen: Color { Color(red: 0.15, green: 0.35, blue: 0.25) }
    
    init(
        memory: MemoryEntry,
        initialCharacterDetails: CharacterDetails? = nil,
        onBackInsteadOfDismiss: (() -> Void)? = nil
    ) {
        self.memory = memory
        self.initialCharacterDetails = initialCharacterDetails
        self.onBackInsteadOfDismiss = onBackInsteadOfDismiss
        let seed = initialCharacterDetails ?? memory.parsedCharacterDetails ?? CharacterDetails()
        _characterDetails = State(initialValue: seed)
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Fixed top bar with blur
                stickyTopBar
                
                ZStack {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(spacing: 20) {
                                simplifiedHeaderSection
                                
                                if !existingCharacters.isEmpty {
                                    existingCharactersSection
                                }
                                
                                mainCharactersSection
                                
                                Spacer(minLength: 140)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .animation(nil, value: characterDetails.characters.count)
                        .onChange(of: characterDetails.characters.count) { _ in
                            if let lastChar = characterDetails.characters.last {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        scrollProxy.scrollTo(lastChar.id, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    
                    VStack(spacing: 0) {
                        Spacer()
                        saveButtonSection
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadExistingCharacters()
        }
        .sheet(isPresented: $showExistingCharactersPicker) {
            ExistingCharactersPickerView(
                existingCharacters: existingCharacters,
                currentCharacters: characterDetails.characters,
                onSelect: { character in
                    addExistingCharacter(character)
                }
            )
        }
    }
    
    // MARK: - Sticky Top Bar
    private var stickyTopBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let onBack = onBackInsteadOfDismiss {
                    onBack()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Tokens.ink)
                    .frame(width: 36, height: 36)
            }
            
            Spacer()
            
            Text("Characters")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Tokens.ink)
            
            Spacer()
            
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            backgroundColor
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        )
    }
    
    // MARK: - Simplified Header Section
    private var simplifiedHeaderSection: some View {
        VStack(spacing: 8) {
            Text("Add Characters")
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Describe the people in this memory")
                .font(Tokens.Typography.subtitle)
                .foregroundColor(Tokens.ink.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    
    // MARK: - Existing Characters Section
    private var existingCharactersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Add")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundColor(Tokens.ink)
                    Text("People from your other memories")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.ink.opacity(0.6))
                }
                Spacer()
                
                if existingCharacters.count > 3 {
                    Button(action: { showExistingCharactersPicker = true }) {
                        Text("See All")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(accentColor)
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(existingCharacters.prefix(6)), id: \.id) { character in
                        QuickAddCharacterButton(
                            character: character,
                            isAdded: isCharacterAlreadyAdded(character),
                            onTap: {
                                addExistingCharacter(character)
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(softGreen.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(softGreen.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Main Characters Section
    private var mainCharactersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if characterDetails.characters.isEmpty {
                invitingEmptyState
            } else {
                ForEach(Array(characterDetails.characters.enumerated()), id: \.element.id) { index, character in
                    StreamlinedCharacterCard(
                        character: $characterDetails.characters[index],
                        index: index,
                        onDelete: { removeCharacter(at: index) }
                    )
                    .id(character.id)
                }
            }
        }
    }
    
    // MARK: - Inviting Empty State
    private var invitingEmptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.15), accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(accentColor)
            }
            
            VStack(spacing: 8) {
                Text("Add people from this memory")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundColor(Tokens.ink)
                
                Text("Help us create better images by describing who was there")
                    .font(Tokens.Typography.subtitle)
                    .foregroundColor(Tokens.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Add Character Button
    private var addCharacterButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                addCharacter()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Add Character")
                    .font(Tokens.Typography.button)
            }
            .foregroundColor(Tokens.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Tokens.bgPrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.78, blue: 0.31),
                                Color(red: 0.95, green: 0.55, blue: 0.23),
                                Color(red: 0.88, green: 0.29, blue: 0.23)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2.5
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
    }
    
    // MARK: - Save Button
    private var saveButton: some View {
        Button(action: saveDetails) {
            saveButtonContent
        }
        .scaleEffect(saveSuccess ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: saveSuccess)
    }
    
    private var saveButtonContent: some View {
        HStack(spacing: 8) {
            if saveSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            Text(saveSuccess ? "Saved!" : "Save")
                .font(Tokens.Typography.button)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(saveButtonBackground)
        .clipShape(Capsule())
        .shadow(color: saveButtonShadowColor, radius: 8, x: 0, y: 4)
    }
    
    private var saveButtonBackground: some View {
        Group {
            if saveSuccess {
                Color.green
            } else {
                LinearGradient(
                    colors: [softGreen, softGreen.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    private var saveButtonShadowColor: Color {
        saveSuccess ? Color.green.opacity(0.3) : softGreen.opacity(0.3)
    }
    
    // MARK: - Save Button Section
    private var saveButtonSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Tokens.ink.opacity(0.1))
            
            VStack(spacing: 12) {
                addCharacterButton
                
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(backgroundColor)
        .shadow(color: Tokens.shadow, radius: 8, x: 0, y: -2)
    }
    
    // MARK: - Actions
    private func addCharacter() {
        var newCharacter = CharacterDetails.Character()
        // Don't set globalCharacterId yet - will be set when user enters name and saves
        characterDetails.characters.append(newCharacter)
    }
    
    private func removeCharacter(at index: Int) {
        characterDetails.characters.remove(at: index)
    }
    
    private func saveDetails() {
        // Link characters to global registry before saving
        let profileID = profileVM.selectedProfile.id
        
        for index in characterDetails.characters.indices {
            let character = characterDetails.characters[index]
            
            // If character has a name but no globalCharacterId, create/find global character
            if !character.name.isEmpty && character.globalCharacterId == nil {
                let globalId = GlobalCharacterManager.shared.findOrCreateGlobalCharacter(
                    name: character.name,
                    profileID: profileID
                )
                characterDetails.characters[index].globalCharacterId = globalId
                print("✅ Linked character '\(character.name)' to global registry (ID: \(globalId.uuidString))")
            }
        }
        
        // Show success animation
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            saveSuccess = true
        }
        
        // Triple-save approach for maximum reliability
        do {
            // 1. Primary: Encode character details and save using KVC
            if let encoded = try? JSONEncoder().encode(characterDetails),
               let jsonString = String(data: encoded, encoding: .utf8) {
                memory.setValue(jsonString, forKey: "characterDetails")
                print("✅ Character details encoded and saved using KVC: \(jsonString.prefix(50))...")
            }
            
            // 2. Backup: Save to UserDefaults as failsafe
            if let encoded = try? JSONEncoder().encode(characterDetails),
               let jsonString = String(data: encoded, encoding: .utf8) {
                UserDefaults.standard.set(jsonString, forKey: "characterDetails_\(memory.id?.uuidString ?? "unknown")")
                print("✅ Character details backed up to UserDefaults")
            }
            
            // 3. Save to Core Data
            try context.save()
            print("✅ Character details saved successfully to Core Data")
            
            // Force refresh the memory object from the persistent store
            context.refresh(memory, mergeChanges: true)
            
            // Post notification to refresh other views
            NotificationCenter.default.post(name: .memorySaved, object: nil)

            FirestoreSyncService.shared.queueMemorySyncWithProfile(memory, profile: profileVM.selectedProfile)
            
            // Success feedback and dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
            }
            
        } catch {
            print("❌ Failed to save character details: \(error)")
            saveSuccess = false
            
            // Still dismiss after error
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismiss()
            }
        }
    }
    
    // MARK: - Existing Characters Management
    
    /// Load all unique characters from global registry
    private func loadExistingCharacters() {
        let profileID = profileVM.selectedProfile.id
        
        // Run migration first to ensure global characters are populated from existing memories
        GlobalCharacterManager.shared.migrateExistingCharacters(for: profileID)
        
        let globalCharacters = GlobalCharacterManager.shared.getAllGlobalCharacters(for: profileID)
        
        // Convert global characters to Character structs with most recent appearance
        existingCharacters = globalCharacters.compactMap { globalChar in
            guard let globalId = globalChar.id,
                  let canonicalName = globalChar.canonicalName else {
                return nil
            }
            
            // Get most recent appearance
            if let mostRecent = GlobalCharacterManager.shared.getMostRecentAppearance(
                globalCharacterId: globalId,
                profileID: profileID
            ) {
                // Return the most recent appearance (already has globalCharacterId set)
                return mostRecent
            } else {
                // No appearances yet, create a minimal character with just the name
                var character = CharacterDetails.Character()
                character.globalCharacterId = globalId
                character.name = canonicalName
                return character
            }
        }
        
        print("✅ Loaded \(existingCharacters.count) existing characters from global registry")
    }
    
    /// Check if a character is already added (by name, case-insensitive)
    private func isCharacterAlreadyAdded(_ character: CharacterDetails.Character) -> Bool {
        let normalizedName = character.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return characterDetails.characters.contains { existingChar in
            existingChar.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedName
        }
    }
    
    /// Add an existing character if not already present
    /// Copies from most recent appearance as starting point
    private func addExistingCharacter(_ character: CharacterDetails.Character) {
        guard !isCharacterAlreadyAdded(character) else {
            print("⚠️ Character '\(character.name)' already added")
            return
        }
        
        // Create a copy of the character for this memory
        // User can edit appearance per-memory
        var newCharacter = character
        
        // Ensure globalCharacterId is set
        if let globalId = character.globalCharacterId {
            newCharacter.globalCharacterId = globalId
        } else if !character.name.isEmpty {
            // If no global ID but has name, find or create global character
            let profileID = profileVM.selectedProfile.id
            let globalId = GlobalCharacterManager.shared.findOrCreateGlobalCharacter(
                name: character.name,
                profileID: profileID
            )
            newCharacter.globalCharacterId = globalId
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            characterDetails.characters.append(newCharacter)
        }
        
        print("✅ Added existing character: \(character.name) (can edit appearance for this memory)")
    }
}

// MARK: - Quick Add Character Button
struct QuickAddCharacterButton: View {
    let character: CharacterDetails.Character
    let isAdded: Bool
    let onTap: () -> Void
    
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    private let softGreen = Color(red: 0.15, green: 0.35, blue: 0.25)
    
    private var quickInfo: String {
        [character.age, character.gender].filter { !$0.isEmpty }.joined(separator: ", ")
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(isAdded ? softGreen.opacity(0.15) : accentColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    if !character.name.isEmpty {
                        Text(String(character.name.prefix(1).uppercased()))
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundColor(isAdded ? softGreen : headerColor)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 22))
                            .foregroundColor(accentColor.opacity(0.7))
                    }
                    
                    if isAdded {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(softGreen)
                            )
                            .offset(x: 20, y: -20)
                    }
                }
                
                // Name
                Text(character.name.isEmpty ? "Unknown" : character.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isAdded ? softGreen : headerColor)
                    .lineLimit(1)
                    .frame(width: 80)
                
                // Quick info or "Added" label
                if isAdded {
                    Text("Added")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(softGreen)
                } else if !quickInfo.isEmpty {
                    Text(quickInfo)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isAdded ? softGreen.opacity(0.06) : Color.white.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isAdded ? softGreen.opacity(0.3) : accentColor.opacity(0.2), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isAdded)
    }
}

// MARK: - Existing Characters Picker View
struct ExistingCharactersPickerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let existingCharacters: [CharacterDetails.Character]
    let currentCharacters: [CharacterDetails.Character]
    let onSelect: (CharacterDetails.Character) -> Void
    
    @State private var searchText = ""
    
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    private let cardColor = Color(red: 1.0, green: 0.97, blue: 0.92)
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    
    private func isAdded(_ character: CharacterDetails.Character) -> Bool {
        let normalizedName = character.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return currentCharacters.contains { existingChar in
            existingChar.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedName
        }
    }
    
    private var filteredCharacters: [CharacterDetails.Character] {
        if searchText.isEmpty {
            return existingCharacters
        }
        return existingCharacters.filter { character in
            character.name.localizedCaseInsensitiveContains(searchText) ||
            character.age.localizedCaseInsensitiveContains(searchText) ||
            character.ethnicity.localizedCaseInsensitiveContains(searchText) ||
            character.hairAndFeatures.localizedCaseInsensitiveContains(searchText) ||
            character.clothes.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search characters...", text: $searchText)
                            .font(.system(size: 16))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredCharacters, id: \.id) { character in
                                ExistingCharacterRow(
                                    character: character,
                                    isAdded: isAdded(character),
                                    onTap: {
                                        onSelect(character)
                                        if !isAdded(character) {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                dismiss()
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Add Characters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(accentColor)
                }
            }
        }
    }
}

// MARK: - Existing Character Row
struct ExistingCharacterRow: View {
    let character: CharacterDetails.Character
    let isAdded: Bool
    let onTap: () -> Void
    
    private let cardColor = Color(red: 1.0, green: 0.97, blue: 0.92)
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    
    private var detailsText: String {
        var details: [String] = []
        if !character.age.isEmpty {
            details.append(character.age)
        }
        if !character.gender.isEmpty {
            details.append(character.gender)
        }
        if !character.ethnicity.isEmpty {
            details.append(character.ethnicity)
        }
        if !character.hairAndFeatures.isEmpty {
            let preview = character.hairAndFeatures.components(separatedBy: ",").first ?? character.hairAndFeatures
            details.append(preview)
        }
        return details.joined(separator: " • ")
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(isAdded ? Color.gray.opacity(0.2) : accentColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    if isAdded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    } else if !character.name.isEmpty {
                        Text(String(character.name.prefix(1).uppercased()))
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundColor(headerColor)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(accentColor.opacity(0.7))
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.name.isEmpty ? "Unknown" : character.name)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundColor(isAdded ? .gray : headerColor)
                    
                    if !detailsText.isEmpty {
                        Text(detailsText)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                if isAdded {
                    Text("Added")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(accentColor)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardColor)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isAdded ? Color.gray.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isAdded)
        .opacity(isAdded ? 0.6 : 1.0)
    }
}

// MARK: - Age Slider
struct AgeSlider: View {
    @Binding var selectedAge: String
    
    @State private var ageValue: Double = 25
    
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let ink = Color(red: 0.18, green: 0.16, blue: 0.15)
    
    var body: some View {
        HStack(spacing: 10) {
            Text("\(Int(ageValue))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(terracotta)
                .frame(width: 36, alignment: .center)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: ageValue)
            
            Slider(value: $ageValue, in: 1...100, step: 1)
                .tint(terracotta)
                .onChange(of: ageValue) { _, newValue in
                    selectedAge = "\(Int(newValue))"
                }
            
            Text("100")
                .font(.system(size: 13))
                .foregroundColor(.gray)
        }
        .onAppear {
            // Initialize slider value from string
            if let ageInt = Int(selectedAge) {
                ageValue = Double(ageInt)
            } else {
                // Try to parse old category values
                switch selectedAge.lowercased() {
                case "child":
                    ageValue = 8
                case "teen":
                    ageValue = 15
                case "adult":
                    ageValue = 35
                case "senior":
                    ageValue = 70
                default:
                    ageValue = 25
                }
                selectedAge = "\(Int(ageValue))"
            }
        }
    }
}

// MARK: - Gender Segmented Picker
struct GenderSegmentedPicker: View {
    @Binding var selectedGender: String
    
    private let genderOptions = ["Male", "Female", "Other"]
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let ink = Color(red: 0.18, green: 0.16, blue: 0.15)
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(genderOptions, id: \.self) { option in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedGender = option
                    }
                }) {
                    Text(option)
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundColor(selectedGender == option ? .white : ink.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedGender == option ? terracotta : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedGender == option ? terracotta : Color.gray.opacity(0.2), lineWidth: selectedGender == option ? 0 : 1)
                        )
                        .shadow(
                            color: selectedGender == option ? terracotta.opacity(0.25) : Color.clear,
                            radius: selectedGender == option ? 4 : 0,
                            x: 0,
                            y: selectedGender == option ? 2 : 0
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(selectedGender == option ? 1.0 : 0.98)
            }
        }
    }
}

// MARK: - Appearance Text Area
struct AppearanceTextArea: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let ink = Color(red: 0.18, green: 0.16, blue: 0.15)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundColor(ink)
            
            TextField("Describe their look: skin tone, hair, build, what they're wearing...", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 15))
                .foregroundColor(ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isFocused ? terracotta.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: isFocused ? 2 : 1)
                        )
                        .shadow(color: isFocused ? terracotta.opacity(0.15) : Color.black.opacity(0.04), radius: isFocused ? 8 : 4, x: 0, y: isFocused ? 4 : 2)
                )
                .focused($isFocused)
                .submitLabel(.done)
        }
    }
}

// MARK: - Character Text Field (grows vertically, with icon + label)
struct CharacterTextField: View {
    let label: String
    let icon: String
    @Binding var text: String
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let ink = Color(red: 0.18, green: 0.16, blue: 0.15)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(terracotta)
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(ink)
            }
            
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 15))
                .foregroundColor(ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isFocused ? terracotta.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: isFocused ? 2 : 1)
                        )
                        .shadow(color: isFocused ? terracotta.opacity(0.15) : Color.black.opacity(0.04), radius: isFocused ? 8 : 4, x: 0, y: isFocused ? 4 : 2)
                )
                .focused($isFocused)
                .submitLabel(.done)
        }
    }
}

// MARK: - Character Text Area (multi-line, with icon + label)
struct CharacterTextArea: View {
    let label: String
    let icon: String
    @Binding var text: String
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let ink = Color(red: 0.18, green: 0.16, blue: 0.15)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(terracotta)
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(ink)
            }
            
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 15))
                .foregroundColor(ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isFocused ? terracotta.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: isFocused ? 2 : 1)
                        )
                        .shadow(color: isFocused ? terracotta.opacity(0.15) : Color.black.opacity(0.04), radius: isFocused ? 8 : 4, x: 0, y: isFocused ? 4 : 2)
                )
                .focused($isFocused)
                .submitLabel(.done)
        }
    }
}

// MARK: - Streamlined Character Card
struct StreamlinedCharacterCard: View {
    @Binding var character: CharacterDetails.Character
    let index: Int
    let onDelete: () -> Void
    
    @FocusState private var isNameFocused: Bool
    @State private var nameText: String = ""
    
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let ink = Color(red: 0.18, green: 0.16, blue: 0.15)
    private let deepGreen = Color(red: 0.07, green: 0.21, blue: 0.13)
    
    // Name text field broken into separate computed property
    private var nameTextField: some View {
        let borderColor = isNameFocused ? terracotta.opacity(0.6) : Color.gray.opacity(0.15)
        let borderWidth: CGFloat = isNameFocused ? 2 : 1
        let shadowColor = isNameFocused ? terracotta.opacity(0.15) : Color.black.opacity(0.04)
        let shadowRadius: CGFloat = isNameFocused ? 8 : 4
        let shadowY: CGFloat = isNameFocused ? 4 : 2
        
        return TextField("Name", text: $character.name, prompt: Text("Character \(index + 1)").foregroundColor(ink.opacity(0.4)))
            .font(.system(size: 18, weight: .semibold, design: .serif))
            .foregroundColor(deepGreen)
            .focused($isNameFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(nameFieldBackground(borderColor: borderColor, borderWidth: borderWidth, shadowColor: shadowColor, shadowRadius: shadowRadius, shadowY: shadowY))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isNameFocused)
    }
    
    private func nameFieldBackground(borderColor: Color, borderWidth: CGFloat, shadowColor: Color, shadowRadius: CGFloat, shadowY: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header: Avatar + Name + Delete
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [terracotta.opacity(0.2), terracotta.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    if !character.name.isEmpty {
                        Text(String(character.name.prefix(1).uppercased()))
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundColor(deepGreen)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(terracotta.opacity(0.7))
                    }
                }
                
                // Name field (inline)
                nameTextField
                
                Spacer()
                
                // Delete button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        onDelete()
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Age slider
            VStack(alignment: .leading, spacing: 8) {
                Text("Age")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(ink)
                
                AgeSlider(selectedAge: $character.age)
            }
            
            // Gender picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Gender")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(ink)
                
                GenderSegmentedPicker(selectedGender: $character.gender)
            }
            
            // Ethnicity
            CharacterTextField(
                label: "Ethnicity",
                icon: "globe",
                text: $character.ethnicity,
                placeholder: "e.g. Indian, Black, White, Hispanic..."
            )
            
            // Hair & Features
            CharacterTextArea(
                label: "Hair & Features",
                icon: "eye",
                text: $character.hairAndFeatures,
                placeholder: "e.g. Black wavy hair, brown eyes, tall..."
            )
            
            // Clothes
            CharacterTextField(
                label: "Clothes",
                icon: "tshirt",
                text: $character.clothes,
                placeholder: "e.g. Blue polo shirt, light jeans..."
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .onAppear {
            // Normalize age to match picker options
            let normalizedAge = normalizeAgeForPicker(character.age)
            if normalizedAge != character.age {
                character.age = normalizedAge
            }
            
            // Initialize gender if empty (don't force a default, let user choose)
            // But ensure it's one of the valid options if set
            if !character.gender.isEmpty && !["Male", "Female", "Other"].contains(character.gender) {
                character.gender = "" // Reset invalid values
            }
        }
    }
    
    // Helper to normalize age values to picker options
    private func normalizeAgeForPicker(_ age: String) -> String {
        let ageLower = age.lowercased()
        
        // Map common age values to picker options
        if ageLower.contains("child") || ageLower.contains("kid") || ageLower.contains("baby") {
            return "Child"
        } else if ageLower.contains("teen") || ageLower.contains("adolescent") {
            return "Teen"
        } else if ageLower.contains("senior") || ageLower.contains("elder") || ageLower.contains("old") {
            return "Senior"
        } else if ageLower.isEmpty {
            return "Adult"
        } else {
            // Try to parse numeric age
            if let ageInt = Int(age.trimmingCharacters(in: CharacterSet.letters.union(.whitespaces))) {
                if ageInt <= 12 {
                    return "Child"
                } else if ageInt <= 17 {
                    return "Teen"
                } else if ageInt >= 65 {
                    return "Senior"
                } else {
                    return "Adult"
                }
            }
            // Default to Adult if can't parse
            return "Adult"
        }
    }
}

// MARK: - Simple Text Field
struct SimpleTextField: View {
    let icon: String
    let label: String
    @Binding var text: String
    let placeholder: String
    
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let softGreen = Color(red: 0.15, green: 0.35, blue: 0.25)
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(accentColor)
                .frame(width: 20)
            
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundColor(softGreen.opacity(0.5)))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(red: 0, green: 0, blue: 0))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.4), lineWidth: 1.5)
        )
    }
}

// MARK: - Detailed Text Field (with icon)
struct DetailedTextField: View {
    let label: String
    let icon: String
    @Binding var text: String
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(accentColor)
                    .frame(width: 20)
                
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(headerColor)
            }
            
            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(
                                    isFocused ? accentColor.opacity(0.6) : Color.gray.opacity(0.25),
                                    lineWidth: isFocused ? 2 : 1
                                )
                        )
                        .shadow(color: isFocused ? accentColor.opacity(0.1) : .clear, radius: 4, x: 0, y: 2)
                )
                .focused($isFocused)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }
}

// MARK: - Streamlined Text Field (Legacy support)
struct StreamlinedTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        DetailedTextField(label: label, icon: "textformat", text: $text, placeholder: placeholder)
    }
}

// MARK: - Enhanced Text Field
struct EnhancedTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accentColor)
                
                Text(title)
                    .font(.custom("Georgia", size: 13))
                    .foregroundColor(headerColor)
                    .fontWeight(.medium)
            }
            
            TextField(placeholder, text: $text)
                .font(.custom("Georgia", size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isFocused ? accentColor.opacity(0.6) : Color.gray.opacity(0.2),
                                    lineWidth: isFocused ? 2 : 1
                                )
                        )
                )
                .focused($isFocused)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }
}

// MARK: - Backward Compatibility Text Field
struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        EnhancedTextField(title: title, text: $text, icon: "textformat", placeholder: placeholder)
    }
}

struct MemoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let ctx = PersistenceController.preview.container.viewContext
        let sample = MemoryEntry(context: ctx)
        sample.prompt = "What did a normal day look like when you were seven?"
        sample.text = "I used to wake up early and..."
        sample.createdAt = Date()
        sample.audioFileURL = nil
        return NavigationView { 
            MemoryDetailView(memory: sample)
                .environmentObject(ProfileViewModel())
        }
    }
}


