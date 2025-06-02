// ChapterJourneyView.swift
// MemoirAI
import AVFoundation
import SwiftUI
import CoreData

struct ChapterJourneyView: View {
    let chapter: Chapter

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var context
    @EnvironmentObject var profileVM: ProfileViewModel

    @FetchRequest(
        entity: MemoryEntry.entity(),
        sortDescriptors: []
    ) var allEntries: FetchedResults<MemoryEntry>

    @State private var selectedPrompt: MemoryPrompt?
    @State private var selectedEntry: MemoryEntry?
    @State private var refreshID = UUID() // Forces full rerender
    @Namespace private var zoomNamespace

    let highlightColor = Color(red: 254/255, green: 242/255, blue: 215/255)
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)

    // Which prompts are done for this profile & chapter
    var completedPromptIDs: Set<UUID> {
        let entriesForProfileAndChapter = allEntries.filter {
            $0.profileID == profileVM.selectedProfile.id &&
            $0.chapter == chapter.title
        }
        let texts = entriesForProfileAndChapter.compactMap { $0.prompt }
        return Set(
            chapter.prompts
                .filter { texts.contains($0.text) }
                .map { $0.id }
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundImageView
                promptNodesView(geo: geo)
                titleBarView(geo: geo)
                backButtonView
                floatingQuoteView
                playerOverlay
            }
//            .navigationBarBackButtonHidden(true)
            .fullScreenCover(item: $selectedPrompt) { prompt in
                RecordingView(
                    prompt:        prompt,
                    chapterTitle:  chapter.title,
                    namespace:     zoomNamespace
                )
                .environmentObject(profileVM)                                    // existing line
                .environment(\.managedObjectContext,                             // 👈 the new line
                             PersistenceController.shared.container.viewContext)
                .id(prompt.id)
                .onDisappear {
                    // force ChapterJourneyView to refresh
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        refreshID = UUID()
                    }
                }
            }

        }
        .id(refreshID)
    }
    
    // MARK: - View Components
    
    private var backgroundImageView: some View {
        Image(chapter.title.lowercased())
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
    }
    
    private func promptNodesView(geo: GeometryProxy) -> some View {
        ForEach(chapter.prompts) { prompt in
            let isCompleted = completedPromptIDs.contains(prompt.id)
            
            MemoryPromptNodeView(
                prompt: prompt,
                isCompleted: isCompleted,
                isLocked: false,
                isSelected: prompt.id == selectedPrompt?.id
            )
            .matchedGeometryEffect(id: prompt.id, in: zoomNamespace)
            .position(
                x: prompt.x * geo.size.width,
                y: prompt.y * geo.size.height
            )
            .onTapGesture {
                handlePromptTap(prompt: prompt, isCompleted: isCompleted)
            }
        }
    }
    
    private func titleBarView(geo: GeometryProxy) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.35))
                .padding(.horizontal, 24)
                .frame(height: 80)

            VStack(spacing: 8) {
                Text("Chapter \(chapter.number) – \(chapter.title)")
                    .font(.customSerifFallback(size: 28))
                    .foregroundColor(deepGreen)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text("\(completedPromptIDs.count) of \(chapter.prompts.count) memories recorded")
                    .font(.subheadline)
                    .foregroundColor(deepGreen)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 50)
        // Remove the fixed offset so it stays centered
         .offset(x: -geo.size.width * 0.140)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    
    private var backButtonView: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.black)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    @ViewBuilder
    private var floatingQuoteView: some View {
        if let prompt = selectedPrompt {
            HStack {
                Spacer(minLength: 24)
                Text("\"\(prompt.text)\"")
                    .font(.system(size: 17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(highlightColor)
                    .cornerRadius(20)
                    .shadow(radius: 4)
                Spacer(minLength: 24)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.move(edge: .bottom))
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    
    // MARK: – Simple dark overlay that auto-plays the memory and can be closed
    @ViewBuilder
    private var playerOverlay: some View {
        if let entry = selectedEntry {
            MemoryPlayerOverlay(entry: entry) {            // ✱ callback to clear selection
                selectedEntry = nil
            }
            .transition(.opacity)                          // nice fade-in/out
            .zIndex(10)                                    // float above everything
        }
    }

    
    // MARK: - Helper Methods
    
    private func handlePromptTap(prompt: MemoryPrompt, isCompleted: Bool) {
        if isCompleted {
            // select existing entry to push detail
            if let entry = allEntries.first(where: {
                $0.profileID == profileVM.selectedProfile.id &&
                $0.chapter == chapter.title &&
                $0.prompt == prompt.text
            }) {
                selectedEntry = entry
            }
        } else {
            // start a new recording
            withAnimation(.spring()) {
                selectedPrompt = prompt
            }
        }
    }
}
struct MemoryPlayerOverlay: View {
    let entry: MemoryEntry
    let onClose: () -> Void

    @State private var player: AVAudioPlayer?

    var body: some View {
        ZStack {
            // 1️⃣ Dim background
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            // 2️⃣ Centered VStack with text + close button
            VStack(spacing: 24) {
                Text("Playing memory…")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Button {
                    player?.stop()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Circle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: -40)   // ◀️ nudge left or right as needed
        }
        .onAppear(perform: startPlayback)
    }

    private func startPlayback() {
        guard
            let urlString = entry.audioFileURL,
            let url = URL(string: urlString)
        else { return }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("⚠️ Could not play audio:", error)
        }
    }
}
