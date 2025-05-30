// ChapterJourneyView.swift
// MemoirAI

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
                hiddenNavigationLink
            }
            .navigationBarBackButtonHidden(true)
            .fullScreenCover(item: $selectedPrompt) { prompt in
                RecordingView(prompt: prompt, chapterTitle: chapter.title, namespace: zoomNamespace)
                    .environmentObject(profileVM)
                    .id(prompt.id)
                    .onDisappear {
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
        .offset(x: -geo.size.width * 0.085)
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
    
    private var hiddenNavigationLink: some View {
        NavigationLink(
            destination: Group {
                if let entry = selectedEntry {
                    MemoryDetailView(memory: entry)
                        .environmentObject(profileVM)
                        .onDisappear {
                            selectedEntry = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                refreshID = UUID()
                            }
                        }
                } else {
                    EmptyView()
                }
            },
            isActive: Binding(
                get: { selectedEntry != nil },
                set: { newValue in
                    if !newValue { selectedEntry = nil }
                }
            ),
            label: { EmptyView() }
        )
        .hidden()
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