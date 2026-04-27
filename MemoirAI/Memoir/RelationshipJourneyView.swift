// RelationshipJourneyView.swift
// MemoirAI — scrollable Candy Crush–style path for Relationships memoir (programmatic art, no raster backgrounds).

import SwiftUI
import CoreData
import Mixpanel
import Vortex
#if canImport(UIKit)
import UIKit
#endif

struct RelationshipJourneyView: View {
    let chapter: Chapter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var profileVM: ProfileViewModel
    @EnvironmentObject private var tutorialCoordinator: TutorialCoordinator

    @FetchRequest(
        entity: MemoryEntry.entity(),
        sortDescriptors: []
    ) private var allEntries: FetchedResults<MemoryEntry>

    @State private var selectedPrompt: MemoryPrompt?
    @State private var selectedEntryID: UUID?
    @State private var refreshID = UUID()
    @Namespace private var zoomNamespace

    @State private var mapContentAppeared = false
    @State private var titleBarAppeared = false
    @State private var animatedProgress: CGFloat = 0

    private let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)

    private var waypoints: [(CGFloat, CGFloat)] { RelationshipJourneyMapConstants.waypoints }
    private var scrollHeight: CGFloat { RelationshipJourneyMapConstants.scrollContentHeight }

    private var completedPromptIDs: Set<UUID> {
        let entriesForProfileAndChapter = allEntries.filter {
            $0.profileID == profileVM.selectedProfile.id &&
            MemoryUserScope.belongsToCurrentUser($0) &&
            $0.chapter == chapter.title
        }
        let texts = entriesForProfileAndChapter.compactMap { $0.prompt }
        return Set(
            chapter.prompts
                .filter { texts.contains($0.text) }
                .map { $0.id }
        )
    }

    private var completedCount: Int { completedPromptIDs.count }

    /// How many prompts are completed from the start with no gaps (trail progress).
    private var contiguousCompletedCount: Int {
        var n = 0
        for (index, prompt) in chapter.prompts.enumerated() {
            if index >= waypoints.count { break }
            if completedPromptIDs.contains(prompt.id) {
                n += 1
            } else {
                break
            }
        }
        return n
    }

    /// First prompt index not yet completed (chapter order) — drives “next step” pulse on the map.
    private var firstIncompleteIndex: Int? {
        chapter.prompts.firstIndex { !completedPromptIDs.contains($0.id) }
    }

    private func refreshJourneyAfterDataChange() {
        context.refreshAllObjects()
        refreshID = UUID()
    }

    private var highlightPromptForTutorial: MemoryPrompt? {
        chapter.prompts.first { !completedPromptIDs.contains($0.id) } ?? chapter.prompts.first
    }

    var body: some View {
        GeometryReader { outerGeo in
            let contentWidth = outerGeo.size.width
            let h = scrollHeight
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            mapScrollContent(width: contentWidth, height: h)
                                .frame(width: contentWidth, height: h)

                            Color.clear
                                .frame(height: 1)
                                .id("relationshipScrollBottom")
                        }
                        .frame(width: contentWidth)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo("relationshipScrollBottom", anchor: .bottom)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.78)) {
                                mapContentAppeared = true
                            }
                            withAnimation(.spring(response: 0.48, dampingFraction: 0.82).delay(0.08)) {
                                titleBarAppeared = true
                            }
                        }
                    }
                    .onChange(of: completedCount) { _, new in
                        let target = CGFloat(new) / CGFloat(max(1, chapter.prompts.count))
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                            animatedProgress = target
                        }
                    }
                    .onAppear {
                        animatedProgress = CGFloat(completedCount) / CGFloat(max(1, chapter.prompts.count))
                    }
                }

                completionConfettiOverlay(width: outerGeo.size.width, height: outerGeo.size.height)
            }
            .overlay(alignment: .top) {
                topChrome(contentWidth: contentWidth)
            }
            .overlay(alignment: .topLeading) {
                backButtonView
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
        .ignoresSafeArea(edges: .bottom)
        .fullScreenCover(item: $selectedPrompt, onDismiss: {
            selectedPrompt = nil
            refreshJourneyAfterDataChange()
        }) { prompt in
            RecordingView(
                prompt: prompt,
                chapterTitle: chapter.title,
                namespace: zoomNamespace,
                onRecordingDismiss: {
                    selectedPrompt = nil
                }
            )
            .environmentObject(profileVM)
            .environmentObject(tutorialCoordinator)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .id(prompt.id)
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

    // MARK: - Map content (scrollable)

    @ViewBuilder
    private func mapScrollContent(width: CGFloat, height: CGFloat) -> some View {
        let accent = relationshipChapterAccentPalette(forChapterNumber: chapter.number)
        let cool = relationshipChapterCoolAccent(forChapterNumber: chapter.number)
        let warmAccent = Color(red: 0.96, green: 0.52, blue: 0.42)

        ZStack(alignment: .topLeading) {
            relationshipBackgroundStack(width: width, height: height)

            RelationshipAmbientGlowSpots(
                width: width,
                height: height,
                accent: warmAccent,
                coolAccent: cool
            )

            RelationshipHillsSilhouetteLayer(width: width, height: height, chapterNumber: chapter.number)

            RelationshipNoiseGrainOverlay(width: width, height: height, chapterNumber: chapter.number)

            ambientParticlesLayer(width: width, height: height)

            VortexView(VortexSystem.memoirJourneyAmbient()) {
                Circle()
                    .fill(.white)
                    .blur(radius: 4)
                    .blendMode(.plusLighter)
                    .frame(width: 28, height: 28)
                    .tag("circle")
            }
            .frame(width: width, height: height)
            .allowsHitTesting(false)

            pathShadowAndGlow(width: width, height: height)

            RelationshipWindingPathShape(waypoints: waypoints)
                .stroke(Color(red: 0.98, green: 0.94, blue: 0.88), style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                .frame(width: width, height: height)

            RelationshipWindingPathShape(waypoints: waypoints)
                .stroke(Color(red: 0.72, green: 0.58, blue: 0.48), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: [16, 20]))
                .frame(width: width, height: height)

            if contiguousCompletedCount > 0 {
                let progressWaypoints = Array(waypoints.prefix(min(contiguousCompletedCount + 1, waypoints.count)))
                RelationshipWindingPathShape(waypoints: progressWaypoints)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.88, blue: 0.42),
                                Color(red: 0.99, green: 0.72, blue: 0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: width, height: height)
                    .shadow(color: Color.orange.opacity(0.55), radius: 12, x: 0, y: 0)
                    .shadow(color: Color.yellow.opacity(0.35), radius: 8, x: 0, y: 0)
            }

            RelationshipPathEdgeStones(width: width, height: height, waypoints: waypoints)

            RelationshipJourneyDecorationsView(
                width: width,
                height: height,
                waypoints: waypoints,
                chapterNumber: chapter.number,
                accentPalette: accent,
                mapAppeared: mapContentAppeared
            )

            nextNodeSparkleLayer(width: width, height: height)

            ForEach(Array(chapter.prompts.enumerated()), id: \.element.id) { index, prompt in
                if index < waypoints.count {
                    let wp = waypoints[index]
                    let x = wp.0 * width
                    let y = wp.1 * height
                    let isCompleted = completedPromptIDs.contains(prompt.id)
                    let isSelected = prompt.id == selectedPrompt?.id
                    let isNextNode = firstIncompleteIndex == index

                    Button {
                        handlePromptTap(prompt: prompt, isCompleted: isCompleted)
                    } label: {
                        ZStack {
                            Ellipse()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.45, green: 0.30, blue: 0.26).opacity(0.55),
                                            Color(red: 0.32, green: 0.22, blue: 0.20).opacity(0.3)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 96, height: 26)
                                .offset(y: 40)
                                .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)

                            RelationshipMapNodeView(
                                stepNumber: index + 1,
                                isCompleted: isCompleted,
                                isSelected: isSelected,
                                isNextNode: isNextNode,
                                mapAppeared: mapContentAppeared,
                                appearanceIndex: index
                            )
                        }
                    }
                    .buttonStyle(RelationshipJourneyNodeButtonStyle())
                    .position(x: x, y: y)
                    .tutorialAnchor(.chapterPickPrompt, when: prompt.id == highlightPromptForTutorial?.id)
                    .background(tutorialAnchorBackground(for: prompt))
                }
            }
        }
    }

    @ViewBuilder
    private func tutorialAnchorBackground(for prompt: MemoryPrompt) -> some View {
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
    }

    private func pathShadowAndGlow(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RelationshipWindingPathShape(waypoints: waypoints)
                .stroke(Color(red: 0.55, green: 0.32, blue: 0.55).opacity(0.25), style: StrokeStyle(lineWidth: 44, lineCap: .round, lineJoin: .round))
                .frame(width: width, height: height)
                .blur(radius: 10)

            RelationshipWindingPathShape(waypoints: waypoints)
                .stroke(Color(red: 0.42, green: 0.26, blue: 0.22), style: StrokeStyle(lineWidth: 28, lineCap: .round, lineJoin: .round))
                .frame(width: width, height: height)
                .offset(x: 1, y: 3)
                .opacity(0.38)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func nextNodeSparkleLayer(width: CGFloat, height: CGFloat) -> some View {
        if let idx = firstIncompleteIndex, idx < waypoints.count {
            let wp = waypoints[idx]
            VortexView(.magic) {
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .blendMode(.plusLighter)
                    .tag("sparkle")
            }
            .frame(width: 160, height: 160)
            .position(x: wp.0 * width, y: wp.1 * height)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func completionConfettiOverlay(width: CGFloat, height: CGFloat) -> some View {
        VortexViewReader { proxy in
            ZStack {
                VortexView(.confetti) {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .tag("square")
                    Circle()
                        .fill(.white)
                        .frame(width: 14)
                        .tag("circle")
                }
                .frame(width: width, height: height)

                Color.clear
                    .frame(width: width, height: height)
                    .onChange(of: completedCount) { old, new in
                        if new > old {
                            proxy.burst()
                        }
                    }
            }
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Top chrome

    private func topChrome(contentWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    relationshipChapterTopFadeColor(forChapterNumber: chapter.number).opacity(0.97),
                    relationshipChapterTopFadeColor(forChapterNumber: chapter.number).opacity(0.65),
                    relationshipChapterTopFadeColor(forChapterNumber: chapter.number).opacity(0.2),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)

            titleBarView(contentWidth: contentWidth)
        }
        .offset(y: titleBarAppeared ? 0 : -28)
        .opacity(titleBarAppeared ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: titleBarAppeared)
    }

    // MARK: - Background & particles

    @ViewBuilder
    private func relationshipBackgroundStack(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            relationshipChapterGradient(forChapterNumber: chapter.number)
                .frame(width: width, height: height)

            Canvas { ctx, size in
                let seeds: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (0.12, 0.08, 0.24, 0.14), (0.88, 0.15, 0.20, 0.12), (0.45, 0.22, 0.30, 0.16),
                    (0.72, 0.35, 0.22, 0.13), (0.20, 0.48, 0.26, 0.15), (0.55, 0.58, 0.32, 0.17),
                    (0.85, 0.62, 0.28, 0.14), (0.30, 0.72, 0.24, 0.12), (0.65, 0.82, 0.34, 0.15),
                    (0.15, 0.88, 0.22, 0.10), (0.50, 0.92, 0.28, 0.12)
                ]
                for s in seeds {
                    let rect = CGRect(
                        x: s.0 * size.width - s.2 * size.width * 0.5,
                        y: s.1 * size.height - s.3 * size.height * 0.5,
                        width: s.2 * size.width,
                        height: s.3 * size.height
                    )
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color.white.opacity(0.28))
                    )
                }
            }
            .frame(width: width, height: height)
            .allowsHitTesting(false)
            .blur(radius: 1.5)
        }
    }

    private func ambientParticlesLayer(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(0..<42, id: \.self) { i in
                let px = pseudoUnit(i * 17 + chapter.number * 3, 97) * width
                let py = pseudoUnit(i * 31 + 11, 101) * height
                let size = 10 + pseudoUnit(i * 13, 5) * 14
                let opacity = 0.14 + pseudoUnit(i * 7, 10) * 0.18
                Group {
                    if i % 3 == 0 {
                        Image(systemName: "heart.fill")
                            .font(.system(size: size * 0.85))
                            .foregroundStyle(Color.pink.opacity(opacity * 2.4))
                    } else {
                        Circle()
                            .fill(Color.white.opacity(opacity * 2.0))
                            .frame(width: size * 0.5, height: size * 0.5)
                    }
                }
                .position(x: px, y: py)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func pseudoUnit(_ seed: Int, _ mod: Int) -> CGFloat {
        let v = abs((seed * 7919 + mod * 104729) % 10000)
        return CGFloat(v) / 10000.0
    }

    private func titleBarView(contentWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text("Chapter \(chapter.number): \(chapter.title)")
                .font(.customSerifFallback(size: 24))
                .foregroundColor(deepGreen)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.58)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(completedCount) of \(chapter.prompts.count) memories recorded")
                .font(.subheadline)
                .foregroundColor(deepGreen.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.42))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.92, green: 0.52, blue: 0.35),
                                    Color(red: 0.98, green: 0.78, blue: 0.42)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geo.size.width * animatedProgress))
                }
            }
            .frame(height: 7)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: contentWidth - 32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 5)
        )
        .padding(.top, 8)
    }

    private var backButtonView: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.2, green: 0.22, blue: 0.28))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
                )
        }
        .padding(.leading, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func handlePromptTap(prompt: MemoryPrompt, isCompleted: Bool) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if isCompleted {
            if let entry = allEntries.first(where: {
                $0.profileID == profileVM.selectedProfile.id &&
                MemoryUserScope.belongsToCurrentUser($0) &&
                $0.chapter == chapter.title &&
                $0.prompt == prompt.text
            }) {
                if let id = entry.id {
                    selectedEntryID = id
                }
            }
        } else {
            Mixpanel.mainInstance().track(event: "Opened Prompt", properties: [
                "chapter_number": chapter.number,
                "chapter_title": chapter.title,
                "prompt_text": prompt.text,
                "is_completed": isCompleted,
                "memoir_mode": "relationships"
            ])
            selectedPrompt = prompt
        }
    }
}
