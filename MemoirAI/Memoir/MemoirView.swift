//
//  MemoirView.swift
//  MemoirAI
//
//  Created by ChatGPT on 5/31/25.
//  “Back” chevron is now black via .tint(.black).
//

import SwiftUI
import CoreData
import RevenueCat
import RevenueCatUI

// MARK: - Custom Serif Font Fallback
extension Font {
    static func customSerifFallback(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        return .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - App Color Theme
struct ColorTheme {
    let softCream      = LinenTheme.paper
    let terracotta     = LinenTheme.accent
    let warmGreen      = LinenTheme.forest
    let deepGreen      = LinenTheme.ink
    let tileBackground = LinenTheme.surface
}

struct MemoirView: View {
    let colors = ColorTheme()
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared
    @State private var showPaywall = false
    @State private var entries: [MemoryEntry] = []
    @State private var navigateToChapter: Int? = nil
    @State private var showModePicker = false
    @State private var showChildNamesSheet = false
    @AppStorage(memoirModeKey) private var memoirModeRaw: String = MemoirMode.normal.rawValue
    private var chapters: [Chapter] { activeChapters }
    private var totalChapters: Int { chapters.count }
    private var memoirMode: MemoirMode { MemoirMode(rawValue: memoirModeRaw) ?? .normal }

    /// Shown at the top of the memoir hub; updates when the mode toggle changes.
    private var memoirPageTitle: String {
        switch memoirMode {
        case .normal: return "My Life Story"
        case .parent: return "Parenthood Memoir"
        case .relationships: return "Relationship Memoir"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                modeToggle
                if let ch = firstIncompleteChapter { currentChapterCard(for: ch) }
                allChaptersTitle
                chaptersGrid
            }
            .adaptiveContentWidth(AdaptiveLayoutPolicy.readableMaxWidth)
            .padding(.bottom, 100)
        }
        .background(colors.softCream.ignoresSafeArea())
        .onAppear {
            migrateLegacyMemoirModeIfNeeded()
            fetchEntries()
            tutorialCoordinator.setVisibleScreen(.memoir)
            tutorialCoordinator.onMemoirViewAppeared(profileID: profileVM.selectedProfile.id)
            promptForChildNamesIfNeeded()
        }
        .onChange(of: memoirModeRaw) { _, _ in
            promptForChildNamesIfNeeded()
        }
        .sheet(isPresented: $showChildNamesSheet) {
            EditChildrenSheet()
                .environmentObject(profileVM)
        }
        .onDisappear {
            tutorialCoordinator.clearAnchor(.memoirPickChapter)
            if tutorialCoordinator.visibleScreen == .memoir {
                tutorialCoordinator.setVisibleScreen(.unknown)
            }
        }
        .toolbarBackground(colors.softCream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $navigateToChapter) { chapterNumber in
            Group {
                if memoirMode == .relationships {
                    GeometryReader { container in
                        RelationshipJourneyView(
                            chapter: preparedChapter(for: chapterNumber),
                            containerSafeAreaInsets: container.safeAreaInsets
                        )
                        .ignoresSafeArea()
                    }
                } else {
                    let destinationChapter = preparedChapter(for: chapterNumber)
                    GeometryReader { container in
                        ChapterJourneyView(
                            chapter: destinationChapter,
                            containerSafeAreaInsets: container.safeAreaInsets
                        )
                        .ignoresSafeArea()
                    }
                }
            }
            .environmentObject(profileVM)
            .environmentObject(tutorialCoordinator)
            .navigationBarHidden(true)
        }
        .tint(.black)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(memoirPageTitle)
                    .font(LinenTheme.heading(22))
                    .foregroundColor(colors.deepGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier("memoirPickerTitle")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showModePicker.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(LinenTheme.body(14, weight: .semibold))
                        .foregroundColor(colors.deepGreen)
                        .frame(width: 36, height: 36)
                        .background(colors.tileBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change memoir type")
                .accessibilityIdentifier("memoirModeChangeButton")
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }

    // MARK: — UI sections
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR CHAPTERS")
                .font(LinenTheme.body(11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(LinenTheme.accent)
            Text("A life, one story at a time.")
                .font(LinenTheme.heading(25))
                .foregroundStyle(LinenTheme.ink)
            HStack {
                Text("\(completedChaptersCount()) of \(totalChapters) chapters completed")
                    .font(LinenTheme.body(13))
                    .foregroundStyle(LinenTheme.secondary)
                Spacer()
            }
            ProgressView(value: Double(completedChaptersCount()), total: Double(max(1, totalChapters)))
                .tint(LinenTheme.forest)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private func currentChapterCard(for chapter: Chapter) -> some View {
        Button {
            navigateToChapter = chapter.number
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(colors.terracotta)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chapter \(chapter.number): \(chapter.title)")
                            .font(LinenTheme.body(16, weight: .semibold))
                            .foregroundColor(colors.deepGreen)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(filledPromptSlotsForChapter(entries: entries, chapter: chapter)) of \(chapter.prompts.count) memories recorded")
                            .font(LinenTheme.body(14))
                            .foregroundColor(colors.deepGreen)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }

                Text("Continue Chapter")
                    .foregroundColor(.white)
                    .font(LinenTheme.body(16, weight: .semibold))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(colors.terracotta)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.tileBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("currentChapterCard")
        .accessibilityHint("Opens this chapter")
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var modeToggle: some View {
        if showModePicker {
            VStack(spacing: 10) {
                ForEach(MemoirMode.allCases, id: \.rawValue) { mode in
                    let isSelected = memoirMode == mode
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            memoirModeRaw = mode.rawValue
                            showModePicker = false
                        }
                        fetchEntries()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: memoirModeIcon(mode))
                                .font(LinenTheme.body(16, weight: .medium))
                                .foregroundColor(isSelected ? .white : colors.terracotta)
                                .frame(width: 32, height: 32)
                                .background(isSelected ? colors.terracotta : colors.terracotta.opacity(0.12))
                                .clipShape(Circle())

                            Text(mode.memoirKindTitle)
                                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? colors.deepGreen : colors.deepGreen.opacity(0.7))

                            Spacer()

                            if isSelected {
                                Circle()
                                    .fill(colors.terracotta)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? colors.tileBackground : Color.clear)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isSelected ? colors.terracotta.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("memoirModeOption_\(mode.rawValue)")
                }

                if memoirMode == .parent {
                    Button {
                        showChildNamesSheet = true
                        showModePicker = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .font(LinenTheme.body(14, weight: .medium))
                                .foregroundColor(colors.terracotta)
                                .frame(width: 32, height: 32)
                                .background(colors.terracotta.opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(editChildrenLabelTitle)
                                    .font(LinenTheme.body(15, weight: .semibold))
                                    .foregroundColor(colors.deepGreen)
                                Text(editChildrenLabelDetail)
                                    .font(LinenTheme.body(12))
                                    .foregroundColor(colors.deepGreen.opacity(0.65))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(LinenTheme.body(12, weight: .semibold))
                                .foregroundColor(colors.deepGreen.opacity(0.5))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(colors.tileBackground.opacity(0.6))
                        .cornerRadius(16)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colors.softCream)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(colors.terracotta.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
        }
    }

    private var editChildrenLabelTitle: String {
        profileVM.selectedProfile.childNames.isEmpty ? "Add children" : "Edit children"
    }

    private var editChildrenLabelDetail: String {
        let names = profileVM.selectedProfile.childNames
        if names.isEmpty { return "Tap to add the kids this book is for" }
        return names.joined(separator: ", ")
    }

    private func promptForChildNamesIfNeeded() {
        if memoirMode == .parent && profileVM.selectedProfile.childNames.isEmpty {
            showChildNamesSheet = true
        }
    }

    private func memoirModeIcon(_ mode: MemoirMode) -> String {
        switch mode {
        case .normal: return "book.fill"
        case .parent: return "figure.and.child.holdinghands"
        case .relationships: return "heart.fill"
        }
    }

    private var allChaptersTitle: some View {
        Text("All Chapters")
            .font(LinenTheme.body(16, weight: .semibold))
            .foregroundColor(colors.deepGreen)
            .padding(.horizontal, 24)
            .padding(.top, 12)
    }

    private var chaptersGrid: some View {
        LazyVGrid(columns: chapterGridColumns, spacing: 16) {
            ForEach(1...chapters.count, id: \.self) { chapterNumber in
                if let chapter = chapters.first(where: { $0.number == chapterNumber }) {
                    let isDone = filledPromptSlotsForChapter(entries: entries, chapter: chapter) >= chapter.prompts.count

                    Button(action: {
                        navigateToChapter = chapterNumber
                    }) {
                        HStack(spacing: 16) {
                            Text(String(format: "%02d", chapterNumber))
                                .font(LinenTheme.heading(24))
                                .foregroundStyle(LinenTheme.accent)
                                .frame(width: 36, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(chapter.title)
                                    .font(LinenTheme.body(16, weight: .medium))
                                    .foregroundStyle(LinenTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Text("\(filledPromptSlotsForChapter(entries: entries, chapter: chapter)) of \(chapter.prompts.count) memories")
                                    .font(LinenTheme.body(12))
                                    .foregroundStyle(LinenTheme.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: isDone ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(isDone ? LinenTheme.forest : LinenTheme.secondary)
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { LinenTheme.line.frame(height: 1) }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("chapterTile\(chapterNumber)")
                    .overlay(
                        Group {
                            if chapterNumber == 1 {
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            tutorialCoordinator.reportAnchor(.memoirPickChapter, rect: geo.frame(in: .global))
                                        }
                                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                            tutorialCoordinator.reportAnchor(.memoirPickChapter, rect: newFrame)
                                        }
                                }
                                .allowsHitTesting(false)
                            }
                        }
                    )
                    .tutorialAnchor(.memoirPickChapter, when: chapterNumber == 1)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var chapterGridColumns: [GridItem] {
        let columnCount = 1
        return Array(
            repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
            count: columnCount
        )
    }

    // MARK: — Data helpers
       private var firstIncompleteChapter: Chapter? {
        chapters.first { filledPromptSlotsForChapter(entries: entries, chapter: $0) < $0.prompts.count }
    }

    private func completedChaptersCount() -> Int {
        chapters.filter { filledPromptSlotsForChapter(entries: entries, chapter: $0) >= $0.prompts.count }.count
    }

    private func fetchEntries() {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileVM.selectedProfile.id)
        do { entries = try PersistenceController.shared.container.viewContext.fetch(request) }
        catch { print("Fetch error:", error) }
    }

    /// Chapter data for journey: image-based layout follows each artwork's trail; Relationships uses its own map layout.
    private func preparedChapter(for idx: Int) -> Chapter {
        guard let base = chapters.first(where: { $0.number == idx }) else {
            return .init(number: idx, title: "Unknown", prompts: [])
        }
        if memoirMode == .relationships {
            return base
        }
        let coordinates = ChapterJourneyNodeLayoutPolicy.coordinates(forChapterTitle: base.title)
        let prompts = zip(base.prompts, coordinates).map { prompt, point in
            MemoryPrompt(text: prompt.text, x: point.x, y: point.y, isPerChild: prompt.isPerChild)
        }
        return .init(number: base.number, title: base.title, prompts: prompts)
    }

    // Check if user has subscription
    private var isSubscribed: Bool {
        subscriptionManager.activeTier != nil
    }
}

// MARK: — ChapterTileView (unchanged)
struct ChapterTileView: View {
    let chapterNumber: Int
    let title: String
    let isLocked: Bool
    let isCurrent: Bool
    let isCompleted: Bool
    let colors: ColorTheme
    @ScaledMetric(relativeTo: .caption) private var reservedTitleHeight: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: isCompleted ? "checkmark" : "book")
                .foregroundColor(colors.deepGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text("Chapter \(chapterNumber)")
                    .font(LinenTheme.body(14)).fontWeight(.semibold)
                    .foregroundColor(colors.deepGreen)
                Text(title)
                    .font(LinenTheme.body(12))
                    .foregroundColor(colors.deepGreen)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: reservedTitleHeight, alignment: .topLeading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(colors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

// Make Int conform to Identifiable for navigation
extension Int: Identifiable {
    public var id: Int { self }
}
