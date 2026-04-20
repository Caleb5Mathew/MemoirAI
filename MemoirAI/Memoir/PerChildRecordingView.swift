// PerChildRecordingView.swift
// MemoirAI — wrapper that walks the user through one RecordingView per child for a per-child prompt slot.

import SwiftUI
import CoreData

struct PerChildRecordingView: View {
    let basePrompt: MemoryPrompt
    let chapterTitle: String
    let childNames: [String]
    let namespace: Namespace.ID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator

    @FetchRequest(
        entity: MemoryEntry.entity(),
        sortDescriptors: []
    ) private var allEntries: FetchedResults<MemoryEntry>

    @State private var currentIndex: Int = 0
    @State private var expandedPrompts: [MemoryPrompt]
    @State private var didInitStart: Bool = false

    init(basePrompt: MemoryPrompt, chapterTitle: String, childNames: [String], namespace: Namespace.ID) {
        self.basePrompt = basePrompt
        self.chapterTitle = chapterTitle
        self.childNames = childNames
        self.namespace = namespace
        // Seed the queue eagerly so the first render already has a prompt to show.
        _expandedPrompts = State(initialValue: expandedChildPrompts(for: basePrompt, childNames: childNames))
    }

    /// Index of the first sub-prompt that does not yet have a saved entry. Used to skip already-recorded children when the user re-enters a partially-filled slot.
    private func firstUnrecordedIndex(in prompts: [MemoryPrompt]) -> Int {
        let entries = allEntries.filter {
            $0.profileID == profileVM.selectedProfile.id &&
            MemoryUserScope.belongsToCurrentUser($0) &&
            chapterTitleMatches($0.chapter, chapterTitle)
        }
        for (i, sub) in prompts.enumerated() {
            if !entries.contains(where: { $0.prompt == sub.text }) {
                return i
            }
        }
        return 0
    }

    var body: some View {
        ZStack {
            if !expandedPrompts.isEmpty, currentIndex < expandedPrompts.count {
                let prompt = expandedPrompts[currentIndex]
                RecordingView(
                    prompt: prompt,
                    chapterTitle: chapterTitle,
                    namespace: namespace,
                    onRecordingDismiss: nil,
                    onSaveComplete: advanceQueue,
                    progressLabel: expandedPrompts.count > 1
                        ? "\(currentIndex + 1) of \(expandedPrompts.count)"
                        : nil
                )
                .environmentObject(profileVM)
                .environmentObject(tutorialCoordinator)
                .environment(\.managedObjectContext,
                             PersistenceController.shared.container.viewContext)
                .id(prompt.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                // Keep the cover on screen while we resolve the starting index; never self-dismiss here,
                // otherwise the cover is torn down before the user ever sees RecordingView.
                Color.clear
            }
        }
        .onAppear {
            guard !didInitStart else { return }
            didInitStart = true
            currentIndex = firstUnrecordedIndex(in: expandedPrompts)
        }
    }

    private func advanceQueue() {
        let nextIndex = currentIndex + 1
        if nextIndex >= expandedPrompts.count {
            dismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            currentIndex = nextIndex
        }
    }
}
