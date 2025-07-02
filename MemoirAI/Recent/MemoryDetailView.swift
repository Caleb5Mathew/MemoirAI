import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import CoreData
import Mixpanel

// MARK: - Character Details Structure
struct CharacterDetails: Codable {
    var characters: [Character] = []
    
    struct Character: Codable, Identifiable {
        let id = UUID()
        var name: String = ""
        var age: String = ""
        var race: String = ""
        var physicalDescription: String = ""
        var clothing: String = ""
        var relationshipToNarrator: String = ""
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
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.managedObjectContext) private var context
    @StateObject private var familyManager = FamilyManager.shared
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
    @State private var refreshTrigger = 0

    private let backgroundColor = Color(red: 1.0, green: 0.96, blue: 0.89)
    private let cardColor = Color(red: 0.98, green: 0.93, blue: 0.80)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    private let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(memory.prompt ?? "")
                    .font(.custom("Georgia-Bold", size: 22))
                    .foregroundColor(headerColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // --- CORRECTED CONTENT BLOCK ---
                VStack(spacing: 20) {
                    if let date = memory.createdAt {
                        Text(dateFormatted(date))
                            .font(.custom("Georgia-Bold", size: 22))
                            .foregroundColor(.black)
                    }

                    // 1. Display the audio player if an audio file exists.
                    if let urlString = memory.audioFileURL,
                       let url = URL(string: urlString) {
                        Button(action: { togglePlayback(url: url) }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .resizable()
                                .frame(width: 64, height: 64)
                                .foregroundColor(.orange)
                        }
                        Text("Tap to listen to this memory")
                            .font(.custom("Georgia", size: 16))
                            .foregroundColor(.black)
                        Divider()
                    }
                    
                    // 2. Display the saved text if it exists.
                    if let saved = memory.text, !saved.isEmpty {
                        Text(saved)
                            .font(.custom("Georgia", size: 18))
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.black)
                            .lineSpacing(4)
                            .padding(.vertical, 8)
                        Divider()
                    }

                    // 3. Display the text editor if in editing mode.
                    if isEditing {
                        TextEditor(text: $draftText)
                            .font(.custom("Georgia", size: 18))
                            .frame(minHeight: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .onAppear { draftText = memory.text ?? "" }
                        Divider()
                    }
                    
                    // 4. Character details enhancement section
                    if memory.isIncomplete {
                        characterEnhancementSection
                    } else if let details = memory.parsedCharacterDetails, !details.characters.isEmpty {
                        characterDetailsSection(details: details)
                    }
                }
                .padding()
                .background(cardColor)
                .cornerRadius(32)
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 4)
                .padding(.horizontal, 24)
                // --- END CORRECTED CONTENT BLOCK ---

                // Family Sharing Section
                if familyManager.currentFamily != nil {
                    familySharingSection
                }

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
                .background(cardColor)
                .cornerRadius(32)
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 4)
                .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
            .onAppear(perform: loadPhotosFromRelationship)
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if familyManager.currentFamily != nil {
                    Button(action: shareWithFamily) {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(terracotta)
                    }
                }
                
                Button(action: { showCharacterDetails = true }) {
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
                        memory.text = draftText
                        do {
                            try context.save()
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
            }
        }
        .alert("Shared with Family!", isPresented: $showFamilyShareSuccess) {
            Button("OK") { }
        } message: {
            Text("Your memory has been shared with \(familyManager.currentFamily?.name ?? "your family"). They can now see and react to it!")
        }
        .sheet(isPresented: $showCharacterDetails) {
            CharacterDetailsQuestionView(memory: memory)
        }
        .onAppear {
            Mixpanel.mainInstance().track(event: "Viewed Memory", properties: [
                "chapter_title": memory.chapter ?? "",
                "prompt_text": memory.prompt ?? "",
                "has_audio": memory.audioFileURL != nil,
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
        .id(refreshTrigger) // Force view refresh when trigger changes
    }
    
    // MARK: - Family Sharing Section
    
    private var familySharingSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share with Family")
                        .font(.headline)
                        .foregroundColor(headerColor)
                    
                    Text("Let \(familyManager.currentFamily?.name ?? "your family") see this memory")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: shareWithFamily) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill")
                        Text("Share")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(terracotta)
                    .cornerRadius(12)
                }
            }
            
            if !familyManager.familyMembers.isEmpty {
                HStack {
                    Text("Family members:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    ForEach(familyManager.familyMembers.prefix(4)) { member in
                        Circle()
                            .fill(terracotta.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(String(member.name.prefix(1)))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(headerColor)
                            )
                    }
                    
                    if familyManager.familyMembers.count > 4 {
                        Text("+\(familyManager.familyMembers.count - 4)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(cardColor)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 4)
        .padding(.horizontal, 24)
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
        if let urlString = memory.audioFileURL, let url = URL(string: urlString) {
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
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundColor(.orange)
                        Text("Enhance for Better Images")
                            .font(.custom("Georgia-Bold", size: 16))
                            .foregroundColor(headerColor)
                    }
                    
                    Text("Add character details to help us create more accurate images")
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: { showCharacterDetails = true }) {
                    Text("Add Details")
                        .font(.custom("Georgia", size: 12))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(terracotta)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func characterDetailsSection(details: CharacterDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.green)
                    Text("Character Details")
                        .font(.custom("Georgia-Bold", size: 16))
                        .foregroundColor(headerColor)
                }
                
                Spacer()
                
                Button(action: { showCharacterDetails = true }) {
                    Text("Edit")
                        .font(.custom("Georgia", size: 12))
                        .foregroundColor(terracotta)
                }
            }
            
            ForEach(details.characters.prefix(3)) { character in
                HStack(spacing: 12) {
                    Circle()
                        .fill(softCream)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(character.name.prefix(1)))
                                .font(.custom("Georgia-Bold", size: 14))
                                .foregroundColor(headerColor)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(character.name.isEmpty ? "Unnamed Character" : character.name)
                            .font(.custom("Georgia", size: 14))
                            .foregroundColor(.black)
                        
                        if !character.age.isEmpty || !character.physicalDescription.isEmpty {
                            Text([character.age, character.physicalDescription].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.custom("Georgia", size: 12))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                }
            }
            
            if details.characters.count > 3 {
                Text("+ \(details.characters.count - 3) more character\(details.characters.count - 3 == 1 ? "" : "s")")
                    .font(.custom("Georgia", size: 12))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Character Details Question View
struct CharacterDetailsQuestionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    
    let memory: MemoryEntry
    @State private var characterDetails: CharacterDetails
    @State private var showingAddCharacter = false
    @State private var currentCharacterIndex = 0
    @State private var saveSuccess = false
    @State private var showFullMemory = false
    
    // Enhanced color scheme
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    private let cardColor = Color(red: 1.0, green: 0.97, blue: 0.92)
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    private let softGreen = Color(red: 0.15, green: 0.35, blue: 0.25)
    private let warmGold = Color(red: 0.95, green: 0.85, blue: 0.65)
    
    init(memory: MemoryEntry) {
        self.memory = memory
        _characterDetails = State(initialValue: memory.parsedCharacterDetails ?? CharacterDetails())
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [backgroundColor, backgroundColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Subtle Header
                        enhancedHeaderSection
                        
                        // Clickable Memory preview
                        enhancedMemoryPreviewSection
                        
                        // Subtle Characters section
                        enhancedCharactersSection
                        
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                
                // Floating Save Button (Bottom Right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        Button(action: saveDetails) {
                            HStack(spacing: 8) {
                                if saveSuccess {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 16))
                                }
                                
                                Text(saveSuccess ? "Saved!" : "Save")
                                    .font(.custom("Georgia-Bold", size: 16))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(saveSuccess ? Color.green : accentColor)
                                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                            )
                        }
                        .scaleEffect(saveSuccess ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: saveSuccess)
                        .padding(.trailing, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                        Text("Cancel")
                            .font(.custom("Georgia", size: 16))
                    }
                    .foregroundColor(headerColor)
                }
            }
        }
    }
    
    // MARK: - Subtle Header Section
    private var enhancedHeaderSection: some View {
        VStack(spacing: 12) {
            Text("Character Details")
                .font(.custom("Georgia-Bold", size: 22))
                .foregroundColor(headerColor)
            
            Text("Add character descriptions to enhance image generation")
                .font(.custom("Georgia", size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
    
    // MARK: - Subtle Clickable Memory Preview
    private var enhancedMemoryPreviewSection: some View {
        Button(action: { showFullMemory = true }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(memory.prompt ?? "Untitled Memory")
                    .font(.custom("Georgia-Bold", size: 16))
                    .foregroundColor(headerColor)
                    .multilineTextAlignment(.leading)
                
                if let text = memory.text, !text.isEmpty {
                    Text(text)
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(.black.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                HStack {
                    Text("Tap to view full memory")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Image(systemName: "chevron.right.circle")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardColor)
                .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .sheet(isPresented: $showFullMemory) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(memory.prompt ?? "Untitled Memory")
                            .font(.custom("Georgia-Bold", size: 22))
                            .foregroundColor(headerColor)
                        
                        if let text = memory.text, !text.isEmpty {
                            Text(text)
                                .font(.custom("Georgia", size: 16))
                                .foregroundColor(.black)
                                .lineSpacing(4)
                        }
                        
                        if let date = memory.createdAt {
                            Text(date, format: .dateTime.weekday().month().day().year())
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                }
                .background(backgroundColor)
                .navigationTitle("Memory")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showFullMemory = false }
                    }
                }
            }
        }
    }
    
    // MARK: - Subtle Characters Section
    private var enhancedCharactersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Characters")
                    .font(.custom("Georgia-Bold", size: 18))
                    .foregroundColor(headerColor)
                
                Spacer()
                
                if !characterDetails.characters.isEmpty {
                    Text("\(characterDetails.characters.count)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            if characterDetails.characters.isEmpty {
                enhancedEmptyCharactersView
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(Array(characterDetails.characters.enumerated()), id: \.element.id) { index, character in
                        EnhancedCharacterCardView(
                            character: $characterDetails.characters[index],
                            index: index,
                            onDelete: { removeCharacter(at: index) }
                        )
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.8))
                        ))
                    }
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: characterDetails.characters.count)
            }
            
            // Enhanced Add Character Button
            enhancedAddCharacterButton
        }
    }
    
    private var enhancedEmptyCharactersView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.dashed")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No characters added yet")
                .font(.custom("Georgia-Bold", size: 16))
                .foregroundColor(headerColor)
            
            Text("Add character descriptions to improve image quality")
                .font(.custom("Georgia", size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardColor.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(warmGold.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                )
        )
    }
    
    // MARK: - Enhanced Add Character Button
    private var enhancedAddCharacterButton: some View {
        Button(action: addCharacter) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Add Character")
                    .font(.custom("Georgia-Bold", size: 17))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
            )
        }
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: characterDetails.characters.count)
    }
    
    // MARK: - Actions
    private func addCharacter() {
        let newCharacter = CharacterDetails.Character()
        characterDetails.characters.append(newCharacter)
    }
    
    private func removeCharacter(at index: Int) {
        characterDetails.characters.remove(at: index)
    }
    
    private func saveDetails() {
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
}

// MARK: - Enhanced Character Card View
struct EnhancedCharacterCardView: View {
    @Binding var character: CharacterDetails.Character
    let index: Int
    let onDelete: () -> Void
    
    @State private var isExpanded = true
    
    private let cardColor = Color(red: 1.0, green: 0.97, blue: 0.92)
    private let accentColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    private let headerColor = Color(red: 0.07, green: 0.21, blue: 0.13)
    private let warmGold = Color(red: 0.95, green: 0.85, blue: 0.65)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with character avatar and controls
            characterHeaderView
            
            if isExpanded {
                // Character details form
                characterFormView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardColor)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(accentColor.opacity(0.2), lineWidth: 1.5)
        )
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isExpanded)
    }
    
    private var characterHeaderView: some View {
        HStack(spacing: 16) {
            // Character avatar
            ZStack {
                Circle()
                    .fill(warmGold.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                if !character.name.isEmpty {
                    Text(String(character.name.prefix(1).uppercased()))
                        .font(.custom("Georgia-Bold", size: 20))
                        .foregroundColor(headerColor)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundColor(accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(character.name.isEmpty ? "Character \(index + 1)" : character.name)
                    .font(.custom("Georgia-Bold", size: 18))
                    .foregroundColor(headerColor)
                
                if !character.age.isEmpty || !character.physicalDescription.isEmpty {
                    Text([character.age, character.physicalDescription].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.custom("Georgia", size: 13))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Expand/collapse button
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 22))
                        .foregroundColor(accentColor)
                }
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var characterFormView: some View {
        VStack(spacing: 16) {
            Divider()
                .background(warmGold.opacity(0.3))
                .padding(.horizontal, 20)
            
            VStack(spacing: 16) {
                EnhancedTextField(title: "Name or Relationship", text: $character.name,
                                icon: "person.circle", placeholder: "Mom, John, My friend Sarah...")
                EnhancedTextField(title: "Age at the Time", text: $character.age,
                                icon: "calendar.circle", placeholder: "35, teenage, elderly...")
                EnhancedTextField(title: "Race/Ethnicity", text: $character.race,
                                icon: "globe.americas", placeholder: "Caucasian, Hispanic, Asian...")
                EnhancedTextField(title: "Physical Description", text: $character.physicalDescription,
                                icon: "eye.circle", placeholder: "Tall, brown hair, blue eyes, glasses...")
                EnhancedTextField(title: "Clothing/Appearance", text: $character.clothing,
                                icon: "tshirt", placeholder: "Blue dress, casual clothes, work uniform...")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
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
        return NavigationView { MemoryDetailView(memory: sample) }
    }
}

