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
    let softCream      = Color(red: 253/255, green: 234/255, blue: 198/255)
    let terracotta     = Color(red: 210/255, green: 112/255, blue:  45/255)
    let warmGreen      = Color(red: 169/255, green: 175/255, blue: 133/255)
    let deepGreen      = Color(red:  39/255, green:  60/255, blue:  34/255)
    let tileBackground = Color(red: 255/255, green: 241/255, blue: 213/255)
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
            VStack(spacing: 24) {
                Text(memoirPageTitle)
                    .font(.customSerifFallback(size: 22))
                    .foregroundColor(colors.deepGreen)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    .padding(.top, 12)

                header
                modeToggle
                if let ch = firstIncompleteChapter { currentChapterCard(for: ch) }
                allChaptersTitle
                chaptersGrid
            }
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
        .navigationDestination(item: $navigateToChapter) { chapterNumber in
            Group {
                if memoirMode == .relationships {
                    RelationshipJourneyView(chapter: preparedChapter(for: chapterNumber))
                } else {
                    ChapterJourneyView(chapter: preparedChapter(for: chapterNumber))
                }
            }
            .environmentObject(profileVM)
            .environmentObject(tutorialCoordinator)
            .navigationBarHidden(true)
        }
        .tint(.black)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showModePicker.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.deepGreen)
                        .frame(width: 34, height: 34)
                        .background(colors.tileBackground)
                        .clipShape(Circle())
                }
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            // Add error handling around PaywallView
            Group {
                if RCSubscriptionManager.shared.offerings?.current?.availablePackages.isEmpty == false {
                    PaywallView(displayCloseButton: true)
                } else {
                    // Fallback view when paywall can't load
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Subscription Temporarily Unavailable")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Please try again later or contact support.")
                            .multilineTextAlignment(.center)
                        
                        Button("Close") {
                            showPaywall = false
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color.white)
                }
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea()
        }
    }

    // MARK: — UI sections
    private var header: some View {
        VStack(spacing: 12) {
            Image("Flower")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .padding(.bottom, 4)

            Text("Hold on to your story")
                .font(.customSerifFallback(size: 30))
                .foregroundColor(colors.deepGreen)
                .multilineTextAlignment(.center)

            Text("\(completedChaptersCount()) of \(totalChapters) chapters completed")
                .font(.subheadline)
                .foregroundColor(colors.deepGreen)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private func currentChapterCard(for chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .foregroundColor(colors.terracotta)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Chapter \(chapter.number): \(chapter.title)")
                        .font(.headline)
                        .foregroundColor(colors.deepGreen)

                    Text("\(filledPromptSlotsForChapter(entries: entries, chapter: chapter)) of \(chapter.prompts.count) memories recorded")
                        .font(.subheadline)
                        .foregroundColor(colors.deepGreen)
                }
            }

            Button(action: {
                navigateToChapter = chapter.number
            }) {
                Text("Continue Chapter")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(colors.terracotta)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(colors.tileBackground)
        .cornerRadius(32)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 6)
        .padding(.horizontal)
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
                                .font(.system(size: 16, weight: .medium))
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
                        .background(isSelected ? colors.tileBackground : Color.clear)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isSelected ? colors.terracotta.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if memoirMode == .parent {
                    Button {
                        showChildNamesSheet = true
                        showModePicker = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.terracotta)
                                .frame(width: 32, height: 32)
                                .background(colors.terracotta.opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(editChildrenLabelTitle)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(colors.deepGreen)
                                Text(editChildrenLabelDetail)
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.deepGreen.opacity(0.65))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
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
            .accessibilityIdentifier("memoirSwitchModeMenu")
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
            .font(.headline)
            .foregroundColor(colors.deepGreen)
            .padding(.horizontal)
            .padding(.top, 12)
    }

    private var chaptersGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(1...chapters.count, id: \.self) { chapterNumber in
                if let chapter = chapters.first(where: { $0.number == chapterNumber }) {
                    let isDone = filledPromptSlotsForChapter(entries: entries, chapter: chapter) >= chapter.prompts.count
                    let isLocked = false

                    Button(action: {
                        navigateToChapter = chapterNumber
                    }) {
                        ChapterTileView(
                            chapterNumber: chapterNumber,
                            title: chapter.title,
                            isLocked: isLocked,
                            isCurrent: false,
                            isCompleted: isDone,
                            colors: colors
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
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
        .padding(.horizontal)
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

    /// Chapter data for journey: image-based layout uses fixed 4 coordinates; Relationships uses raw prompts (layout in `RelationshipJourneyView`).
    private func preparedChapter(for idx: Int) -> Chapter {
        guard let base = chapters.first(where: { $0.number == idx }) else {
            return .init(number: idx, title: "Unknown", prompts: [])
        }
        if memoirMode == .relationships {
            return base
        }
        let coords: [(CGFloat, CGFloat)] = [(0.88,0.80),(0.55,0.63),(0.85,0.43),(0.68,0.28)]
        let prompts = zip(base.prompts, coords).map { (p,c) in
            MemoryPrompt(text: p.text, x: c.0, y: c.1, isPerChild: p.isPerChild)
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isCompleted ? "checkmark" : "book")
                .foregroundColor(colors.deepGreen)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Chapter \(chapterNumber)")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(colors.deepGreen)
                Text(title)
                    .font(.caption)
                    .foregroundColor(colors.deepGreen)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(colors.tileBackground)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

// Make Int conform to Identifiable for navigation
extension Int: Identifiable {
    public var id: Int { self }
}
