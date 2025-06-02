import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import CoreData
import Mixpanel

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

                VStack(spacing: 20) {
                    if let date = memory.createdAt {
                        Text(dateFormatted(date))
                            .font(.custom("Georgia-Bold", size: 22))
                            .foregroundColor(.black)
                    }
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
                        if let saved = memory.text, !saved.isEmpty {
                            Text(saved)
                                .font(.custom("Georgia", size: 18))
                                .multilineTextAlignment(.leading)
                                .foregroundColor(.black)
                                .lineSpacing(4)
                                .padding(.vertical, 8)
                        }
                        Divider()
                    }
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
                }
                .padding()
                .background(cardColor)
                .cornerRadius(32)
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 4)
                .padding(.horizontal, 24)

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
                // Family share button (only show if user has a family)
                if familyManager.currentFamily != nil {
                    Button(action: shareWithFamily) {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(terracotta)
                    }
                }
                
                Button(action: shareMemory) {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Button(action: {
                    if isEditing {
                        // User just tapped "Done" — write back and save
                        memory.text = draftText
                        do {
                            try context.save()
                        } catch {
                            print("Failed to save edited text:", error)
                        }
                    } else {
                        // User just tapped "Edit" — seed the editor
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
        .onAppear {
            // Track memory viewed
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
            
            // Show family member avatars
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
        
        // Check if already shared
        let alreadyShared = familyManager.sharedStories.contains { story in
            story.memoryEntryId == memory.id && story.familyGroupId == familyId
        }
        
        if alreadyShared {
            // Could show "Already shared" message
            return
        }
        
        familyManager.shareStory(memory, with: familyId)
        showFamilyShareSuccess = true
        
        // Add haptic feedback
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
