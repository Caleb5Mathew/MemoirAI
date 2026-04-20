// ChapterJourneyView.swift
// MemoirAI
import SwiftUI
import CoreData
import Mixpanel
#if canImport(UIKit)
import UIKit
#endif

struct ChapterJourneyView: View {
    let chapter: Chapter

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var context
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator

    @FetchRequest(
        entity: MemoryEntry.entity(),
        sortDescriptors: []
    ) var allEntries: FetchedResults<MemoryEntry>

    @State private var selectedPrompt: MemoryPrompt?
    @State private var selectedPerChildPrompt: MemoryPrompt?
    @State private var selectedEntryID: UUID?
    @State private var refreshID = UUID() // Forces full rerender
    @Namespace private var zoomNamespace

    let highlightColor = Color(red: 254/255, green: 242/255, blue: 215/255)
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)

    private var childNames: [String] {
        profileVM.selectedProfile.childNames
    }

    private var chapterEntries: [MemoryEntry] {
        allEntries.filter {
            $0.profileID == profileVM.selectedProfile.id &&
            MemoryUserScope.belongsToCurrentUser($0) &&
            chapterTitleMatches($0.chapter, chapter.title)
        }
    }

    /// Effective child count for a prompt slot's stacked node rendering.
    private func childCount(for prompt: MemoryPrompt) -> Int {
        guard prompt.isPerChild else { return 1 }
        return max(1, childNames.count)
    }

    /// How many of a per-child slot's sub-prompts have a saved entry.
    private func completedChildCount(for prompt: MemoryPrompt) -> Int {
        guard prompt.isPerChild else { return 0 }
        let expanded = expandedChildPrompts(for: prompt, childNames: childNames)
        let entries = chapterEntries
        return expanded.filter { sub in
            entries.contains(where: { $0.prompt == sub.text })
        }.count
    }

    // Which prompts are done for this profile & chapter
    var completedPromptIDs: Set<UUID> {
        let entriesForProfileAndChapter = chapterEntries
        let legacySameNumber = allChaptersLegacyKnownPrompts.first { $0.number == chapter.number }
        let useLegacyIndexMatch = currentMemoirMode() == .normal
            && allChapters.contains(where: { $0.number == chapter.number && $0.title == chapter.title })
            && legacySameNumber != nil
        return Set(
            chapter.prompts.enumerated().compactMap { index, prompt -> UUID? in
                if prompt.isPerChild {
                    let expanded = expandedChildPrompts(for: prompt, childNames: childNames)
                    let allDone = !expanded.isEmpty && expanded.allSatisfy { sub in
                        entriesForProfileAndChapter.contains(where: { $0.prompt == sub.text })
                    }
                    return allDone ? prompt.id : nil
                }
                if entriesForProfileAndChapter.contains(where: { $0.prompt == prompt.text }) {
                    return prompt.id
                }
                if useLegacyIndexMatch,
                   let legacy = legacySameNumber,
                   index < legacy.prompts.count,
                   entriesForProfileAndChapter.contains(where: { $0.prompt == legacy.prompts[index].text }) {
                    return prompt.id
                }
                return nil
            }
        )
    }

    /// Merge background saves into this context and bump identity so `@FetchRequest` + completion UI update promptly.
    private func refreshJourneyAfterDataChange() {
        context.refreshAllObjects()
        refreshID = UUID()
    }

    /// First incomplete prompt in this chapter (fallback: first prompt) — tutorial spotlight target.
    private var highlightPromptForTutorial: MemoryPrompt? {
        chapter.prompts.first { !completedPromptIDs.contains($0.id) } ?? chapter.prompts.first
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundImageView
                promptNodesView(geo: geo)
                titleBarView(geo: geo)
                backButtonView
                floatingQuoteView
            }
//            .navigationBarBackButtonHidden(true)
            .fullScreenCover(item: $selectedPrompt, onDismiss: {
                selectedPrompt = nil
                refreshJourneyAfterDataChange()
            }) { prompt in
                RecordingView(
                    prompt:        prompt,
                    chapterTitle:  chapter.title,
                    namespace:     zoomNamespace,
                    onRecordingDismiss: {
                        selectedPrompt = nil
                    }
                )
                .environmentObject(profileVM)                                    // existing line
                .environmentObject(tutorialCoordinator)
                .environment(\.managedObjectContext,                             // 👈 the new line
                             PersistenceController.shared.container.viewContext)
                .id(prompt.id)
            }
            .fullScreenCover(item: $selectedPerChildPrompt, onDismiss: {
                selectedPerChildPrompt = nil
                refreshJourneyAfterDataChange()
            }) { basePrompt in
                PerChildRecordingView(
                    basePrompt: basePrompt,
                    chapterTitle: chapter.title,
                    childNames: childNames,
                    namespace: zoomNamespace
                )
                .environmentObject(profileVM)
                .environmentObject(tutorialCoordinator)
                .environment(\.managedObjectContext,
                             PersistenceController.shared.container.viewContext)
                .id(basePrompt.id)
            }

        }
        .id(refreshID)
        .navigationDestination(item: $selectedEntryID) { memoryID in
            Group {
                if let entry = allEntries.first(where: { $0.id == memoryID }) {
                    MemoryDetailView(memory: entry)
                        .environmentObject(profileVM)
                } else {
                    Text("Memory not found")
                        .font(.headline)
                }
            }
        }
        .onAppear {
            tutorialCoordinator.setVisibleScreen(.chapterJourney)
            tutorialCoordinator.onChapterJourneyAppeared(profileID: profileVM.selectedProfile.id)
        }
        .onDisappear {
            tutorialCoordinator.clearAnchor(.chapterPickPrompt)
            if tutorialCoordinator.visibleScreen == .chapterJourney {
                tutorialCoordinator.setVisibleScreen(.unknown)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tutorialDismissToHome)) { _ in
            selectedPrompt = nil
            dismiss()
        }
    }

    // MARK: - View Components

    private var backgroundImageView: some View {
        Group {
            let assetName = chapterImageAssetName(for: chapter.title)
            #if canImport(UIKit)
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(red: 0.22, green: 0.22, blue: 0.24)
            }
            #else
            Image(assetName)
                .resizable()
                .scaledToFill()
            #endif
        }
        .ignoresSafeArea()
    }

    private func promptNodesView(geo: GeometryProxy) -> some View {
        ForEach(chapter.prompts) { prompt in
            let isCompleted = completedPromptIDs.contains(prompt.id)
            let isCurrentlySelected = prompt.id == selectedPrompt?.id

            MemoryPromptNodeView(
                prompt: prompt,
                isCompleted: isCompleted,
                isLocked: false,
                isSelected: isCurrentlySelected,
                childCount: childCount(for: prompt),
                completedChildCount: completedChildCount(for: prompt)
            )
            .matchedGeometryEffect(id: prompt.id, in: zoomNamespace)
            .tutorialAnchor(.chapterPickPrompt, when: prompt.id == highlightPromptForTutorial?.id)
            .background(
                Group {
                    if prompt.id == highlightPromptForTutorial?.id {
                        GeometryReader { inner in
                            Color.clear
                                .onAppear {
                                    tutorialCoordinator.reportAnchor(.chapterPickPrompt, rect: inner.frame(in: .global))
                                }
                                .onChange(of: inner.frame(in: .global)) { _, newFrame in
                                    tutorialCoordinator.reportAnchor(.chapterPickPrompt, rect: newFrame)
                                }
                        }
                    }
                }
            )
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
                Text("Chapter \(chapter.number): \(chapter.title)")
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
        // Commented out to prevent flash when presenting recording screen
        // The fullScreenCover shows the prompt anyway, so this is redundant
        /*
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
        */
        EmptyView()
    }

    // MARK: - Helper Methods

    private func handlePromptTap(prompt: MemoryPrompt, isCompleted: Bool) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        if prompt.isPerChild {
            let expanded = expandedChildPrompts(for: prompt, childNames: childNames)
            let entries = chapterEntries
            let remaining = expanded.filter { sub in
                !entries.contains(where: { $0.prompt == sub.text })
            }

            if remaining.isEmpty {
                // All children recorded: open detail for the first child's entry.
                if let first = expanded.first,
                   let entry = entries.first(where: { $0.prompt == first.text }),
                   let id = entry.id {
                    selectedEntryID = id
                }
                return
            }

            Mixpanel.mainInstance().track(event: "Opened Prompt", properties: [
                "chapter_number": chapter.number,
                "chapter_title": chapter.title,
                "prompt_text": prompt.text,
                "is_completed": isCompleted,
                "per_child_count": expanded.count
            ])

            if expanded.count == 1 {
                // Single child (or no kids): open a regular RecordingView with the substituted text.
                selectedPrompt = remaining.first
            } else {
                selectedPerChildPrompt = prompt
            }
            return
        }

        if isCompleted {
            // select existing entry to push detail (including pre-rename prompt text at same index)
            let promptIndex = chapter.prompts.firstIndex { $0.id == prompt.id }
            let legacyChapter = allChaptersLegacyKnownPrompts.first { $0.number == chapter.number }
            let useLegacyIndexMatch = currentMemoirMode() == .normal
                && allChapters.contains(where: { $0.number == chapter.number && $0.title == chapter.title })
                && legacyChapter != nil
            if let entry = allEntries.first(where: { e in
                guard e.profileID == profileVM.selectedProfile.id,
                      MemoryUserScope.belongsToCurrentUser(e),
                      chapterTitleMatches(e.chapter, chapter.title) else { return false }
                if e.prompt == prompt.text { return true }
                if let i = promptIndex, useLegacyIndexMatch, let leg = legacyChapter,
                   i < leg.prompts.count, e.prompt == leg.prompts[i].text {
                    return true
                }
                return false
            }) {
                if let id = entry.id {
                    selectedEntryID = id
                }
            }
        } else {
            // Track prompt opened
            Mixpanel.mainInstance().track(event: "Opened Prompt", properties: [
                "chapter_number": chapter.number,
                "chapter_title": chapter.title,
                "prompt_text": prompt.text,
                "is_completed": isCompleted
            ])

            // start a new recording (no animation to prevent visual flash)
            selectedPrompt = prompt
        }
    }
}
