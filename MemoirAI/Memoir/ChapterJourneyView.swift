// ChapterJourneyView.swift
// MemoirAI
import SwiftUI
import CoreData
import Mixpanel
#if canImport(UIKit)
import UIKit
#endif

enum ChapterJourneyLayoutPolicy {
    static let canonicalArtworkSize = CGSize(width: 1_684, height: 2_528)

    static func artworkFrame(in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0,
              bounds.width.isFinite, bounds.height.isFinite else {
            return CGRect(origin: bounds.origin, size: .zero)
        }

        let scale = max(
            bounds.width / canonicalArtworkSize.width,
            bounds.height / canonicalArtworkSize.height
        )
        let filledSize = CGSize(
            width: canonicalArtworkSize.width * scale,
            height: canonicalArtworkSize.height * scale
        )
        return CGRect(
            x: bounds.midX - filledSize.width / 2,
            y: bounds.minY,
            width: filledSize.width,
            height: filledSize.height
        )
    }

    static func point(normalizedX: CGFloat, normalizedY: CGFloat, in artworkFrame: CGRect) -> CGPoint {
        CGPoint(
            x: artworkFrame.minX + min(max(normalizedX, 0), 1) * artworkFrame.width,
            y: artworkFrame.minY + min(max(normalizedY, 0), 1) * artworkFrame.height
        )
    }
}

struct ChapterJourneyView: View {
    let chapter: Chapter
    let containerSafeAreaInsets: EdgeInsets
    let artworkAssetNameOverride: String?
    let memoirMode: MemoirMode

    init(
        chapter: Chapter,
        containerSafeAreaInsets: EdgeInsets,
        artworkAssetNameOverride: String? = nil,
        memoirMode: MemoirMode = currentMemoirMode()
    ) {
        self.chapter = chapter
        self.containerSafeAreaInsets = containerSafeAreaInsets
        self.artworkAssetNameOverride = artworkAssetNameOverride
        self.memoirMode = memoirMode
    }

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

    let highlightColor = LinenTheme.paper
    let deepGreen = LinenTheme.ink
    private let headerSurface = LinenTheme.paper

    private var childNames: [String] {
        profileVM.selectedProfile.childNames
    }

    private var chapterEntries: [MemoryEntry] {
        allEntries.filter {
            $0.profileID == profileVM.selectedProfile.id &&
            MemoryUserScope.belongsToCurrentUser($0) &&
            chapterTitleMatches($0.chapter, chapter.title, memoirMode: memoirMode)
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
            entries.contains(where: { parentPromptTextsIncludingPrevious(sub.text, chapterTitle: chapter.title).contains($0.prompt ?? "") })
        }.count
    }

    // Which prompts are done for this profile & chapter
    var completedPromptIDs: Set<UUID> {
        let entriesForProfileAndChapter = chapterEntries
        let legacySameNumber = allChaptersLegacyKnownPrompts.first { $0.number == chapter.number }
        let useLegacyIndexMatch = memoirMode == .normal
            && allChapters.contains(where: { $0.number == chapter.number && $0.title == chapter.title })
            && legacySameNumber != nil
        return Set(
            chapter.prompts.enumerated().compactMap { index, prompt -> UUID? in
                if prompt.isPerChild {
                    let expanded = expandedChildPrompts(for: prompt, childNames: childNames)
                    let allDone = !expanded.isEmpty && expanded.allSatisfy { sub in
                        entriesForProfileAndChapter.contains(where: { parentPromptTextsIncludingPrevious(sub.text, chapterTitle: chapter.title).contains($0.prompt ?? "") })
                    }
                    return allDone ? prompt.id : nil
                }
                if entriesForProfileAndChapter.contains(where: { parentPromptTextsIncludingPrevious(prompt.text, chapterTitle: chapter.title).contains($0.prompt ?? "") }) {
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
            let viewportSize = geo.size
            let artworkFrame = ChapterJourneyLayoutPolicy.artworkFrame(
                in: CGRect(origin: .zero, size: viewportSize)
            )
            ZStack(alignment: .top) {
                ScrollView(.vertical) {
                    ZStack {
                        Color(red: 0.84, green: 0.80, blue: 0.68)

                        ZStack {
                            chapterArtwork

                            GeometryReader { canvas in
                                promptNodesView(geo: canvas)
                            }
                        }
                        .frame(width: artworkFrame.width, height: artworkFrame.height)
                        .position(x: artworkFrame.midX, y: artworkFrame.midY)

                        floatingQuoteView
                    }
                    .frame(width: viewportSize.width, height: artworkFrame.height)
                    .clipped()
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: viewportSize.width, height: viewportSize.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .top) {
                headerStack
                    .padding(.top, containerSafeAreaInsets.top + 8)
            }
//            .navigationBarBackButtonHidden(true)
            .fullScreenCover(item: $selectedPrompt, onDismiss: {
                selectedPrompt = nil
                refreshJourneyAfterDataChange()
            }) { prompt in
                RecordingView(
                    prompt:        prompt,
                    chapterTitle:  chapter.title,
                    memoirMode:    memoirMode,
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
                    childNames: childNames
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
                        .font(LinenTheme.body(16, weight: .semibold))
                }
            }
        }
        .analyticsScreen("chapter_journey")
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

    private var chapterArtwork: some View {
        Group {
            let assetName = artworkAssetNameOverride ?? chapterImageAssetName(for: chapter.title)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func promptNodesView(geo: GeometryProxy) -> some View {
        ForEach(chapter.prompts) { prompt in
            let isCompleted = completedPromptIDs.contains(prompt.id)
            MemoryPromptNodeView(
                prompt: prompt,
                isCompleted: isCompleted,
                isLocked: false,
                isSelected: false,
                childCount: childCount(for: prompt),
                completedChildCount: completedChildCount(for: prompt)
            )
            .accessibilityIdentifier("chapterPromptNode")
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
            .position(ChapterJourneyLayoutPolicy.point(
                normalizedX: prompt.x,
                normalizedY: prompt.y,
                in: CGRect(origin: .zero, size: geo.size)
            ))
            .onTapGesture {
                handlePromptTap(prompt: prompt, isCompleted: isCompleted)
            }
        }
    }

    private var headerStack: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 6) {
                Text("Chapter \(chapter.number): \(chapter.title)")
                    .font(LinenTheme.heading(25))
                    .foregroundColor(deepGreen)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.58)
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("chapterJourneyTitle")

                Text("\(completedPromptIDs.count) of \(chapter.prompts.count) memories recorded")
                    .font(LinenTheme.body(13))
                    .foregroundColor(LinenTheme.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("chapterJourneyProgress")
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(LinenTheme.body(22, weight: .semibold))
                    .foregroundColor(deepGreen)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chapterJourneyBack")
            .padding(.leading, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(headerSurface)
                .shadow(color: LinenTheme.ink.opacity(0.08), radius: 12, y: 5)
        )
        .padding(.horizontal, 16)
        .zIndex(100)
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
                    .font(LinenTheme.body(17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
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
                !entries.contains(where: { parentPromptTextsIncludingPrevious(sub.text, chapterTitle: chapter.title).contains($0.prompt ?? "") })
            }

            if remaining.isEmpty {
                // All children recorded: open detail for the first child's entry.
                if let first = expanded.first,
                   let entry = entries.first(where: { parentPromptTextsIncludingPrevious(first.text, chapterTitle: chapter.title).contains($0.prompt ?? "") }),
                   let id = entry.id {
                    selectedEntryID = id
                }
                return
            }

            ProductAnalytics.shared.track("Opened Prompt", [
                    "chapter_number": chapter.number,
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
            let useLegacyIndexMatch = memoirMode == .normal
                && allChapters.contains(where: { $0.number == chapter.number && $0.title == chapter.title })
                && legacyChapter != nil
            if let entry = allEntries.first(where: { e in
                guard e.profileID == profileVM.selectedProfile.id,
                      MemoryUserScope.belongsToCurrentUser(e),
                      chapterTitleMatches(
                        e.chapter,
                        chapter.title,
                        memoirMode: memoirMode
                      ) else { return false }
                if parentPromptTextsIncludingPrevious(prompt.text, chapterTitle: chapter.title).contains(e.prompt ?? "") { return true }
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
            ProductAnalytics.shared.track("Opened Prompt", [
                    "chapter_number": chapter.number,
                    "is_completed": isCompleted
                ])

            // start a new recording (no animation to prevent visual flash)
            selectedPrompt = prompt
        }
    }
}
