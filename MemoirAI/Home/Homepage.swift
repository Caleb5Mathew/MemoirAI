// HomepageView.swift
// MemoirAI

import SwiftUI
import CoreData

struct HomepageView: View {
    // MARK: – Environment & Context
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let openStorybook: () -> Void

    // MARK: – State
    @State private var selectedTab = 0
    let promptOfTheDay = "Tell me about your first job."
    @State private var promptCompleted: Bool = false

    @State private var entries: [MemoryEntry] = []
    @State private var availableWidth: CGFloat = 390

    @State private var showMemoirPicker = false
    @State private var pendingNavigateToMemoir = false
    @State private var navigateToMemoir = false
    @AppStorage("hasChosenMemoirMode") private var hasChosenMemoirMode = false

    // MARK: – Computed Properties

    /// Total memories completed (across all chapters)
    private var completedMemoriesCount: Int {
        entries.filter { entry in
            guard let prompt = entry.prompt else { return false }
            return activeChapters.contains { chapter in
                chapterTitleMatches(entry.chapter, chapter.title)
                    && normalChapterPromptTextsIncludingLegacy(for: chapter).contains(prompt)
            }
        }.count
    }
    
    /// Completion percentage (0-100)
    private var completionPercentage: Int {
        let totalMemories = activeChapters.reduce(0) { $0 + $1.prompts.count }
        guard totalMemories > 0 else { return 0 }
        return Int((Double(completedMemoriesCount) / Double(totalMemories)) * 100)
    }

    // MARK: – Body

    var body: some View {
        Group {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profileVM.selectedProfile.name.isEmpty ? "Welcome to Memoir" : "Hello, \(profileVM.selectedProfile.name).")
                            .font(LinenTheme.heading(30))
                            .tracking(-0.9)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Keep the stories that matter.")
                            .font(LinenTheme.body(14))
                            .foregroundStyle(LinenTheme.secondary)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 6)

                    Button {
                        if hasChosenMemoirMode { navigateToMemoir = true }
                        else { showMemoirPicker = true }
                    } label: {
                        HStack(spacing: 16) {
                            if !dynamicTypeSize.isAccessibilitySize && availableWidth >= 360 {
                                Image("LinenJourney")
                                    .resizable().scaledToFill()
                                    .frame(width: availableWidth < 390 ? 88 : 100, height: 151)
                                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 55, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 55))
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your\nMemoir")
                                    .font(LinenTheme.heading(29))
                                    .tracking(-0.9)
                                    .lineSpacing(-5)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Tell your story.").font(LinenTheme.body(13))
                                ProgressView(value: Double(min(100, completionPercentage)), total: 100)
                                    .tint(LinenTheme.accent)
                                    .accessibilityLabel("Memoir completion")
                                Text("\(completionPercentage)%")
                                    .font(LinenTheme.body(12, weight: .semibold))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 17))
                                .frame(width: 37, height: 37)
                                .overlay(Circle().strokeBorder(lineWidth: 1))
                        }
                        .foregroundStyle(LinenTheme.ink)
                        .padding(21)
                        .frame(maxWidth: .infinity, minHeight: 193, alignment: .leading)
                        .background(LinenTheme.card, in: RoundedRectangle(cornerRadius: 25))
                        .contentShape(RoundedRectangle(cornerRadius: 25))
                    }
                    .buttonStyle(.plain)
                        .tutorialAnchor(.homeContinueMemoir)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { tutorialCoordinator.reportAnchor(.homeContinueMemoir, rect: geo.frame(in: .global)) }
                                    .onChange(of: geo.frame(in: .global)) { _, f in tutorialCoordinator.reportAnchor(.homeContinueMemoir, rect: f) }
                            }
                        )
                        .accessibilityIdentifier("tutorialContinueYourMemoir")
                        
                    Button(action: openStorybook) {
                        HStack(spacing: 16) {
                            if !dynamicTypeSize.isAccessibilitySize && availableWidth >= 360 {
                            VStack(alignment: .center, spacing: 5) {
                                Text("MEMOIR").font(LinenTheme.body(8, weight: .semibold)).tracking(1)
                                Text("A\nlife\nto\nkeep.")
                                    .font(LinenTheme.heading(20))
                                    .tracking(-0.7)
                                    .lineSpacing(-4)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                Image("LinenJourney").resizable().scaledToFill().frame(width: 65, height: 25).clipped()
                            }
                            .foregroundStyle(LinenTheme.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 11)
                            .frame(width: 91, height: 151)
                            .background(Color(red: 0.73, green: 0.63, blue: 0.45), in: UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 8, topTrailingRadius: 8))
                            .rotationEffect(.degrees(8))
                            .dynamicTypeSize(.medium)
                            .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your\nBook")
                                    .font(LinenTheme.heading(29))
                                    .tracking(-0.9)
                                    .lineSpacing(-5)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Bring it to life in print.").font(LinenTheme.body(13))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 17))
                                .frame(width: 37, height: 37)
                                .overlay(Circle().strokeBorder(lineWidth: 1))
                        }
                        .foregroundStyle(LinenTheme.onAccent)
                        .padding(21)
                        .frame(maxWidth: .infinity, minHeight: 193, alignment: .leading)
                        .background(LinenTheme.forest, in: RoundedRectangle(cornerRadius: 25))
                        .contentShape(RoundedRectangle(cornerRadius: 25))
                    }
                    .buttonStyle(.plain)
                        .tutorialAnchor(.homeYourBook)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { tutorialCoordinator.reportAnchor(.homeYourBook, rect: geo.frame(in: .global)) }
                                    .onChange(of: geo.frame(in: .global)) { _, f in tutorialCoordinator.reportAnchor(.homeYourBook, rect: f) }
                            }
                        )
                        .accessibilityIdentifier("tutorialYourBook")

                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .adaptiveContentWidth(560)
            }
            .linenScreen()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .onAppear {
                tutorialCoordinator.setVisibleScreen(.home)
                resetDailyPromptIfNeeded()
                migrateLegacyUnassignedMemories()
                fetchEntries()

            }
            .onDisappear {
                tutorialCoordinator.clearAnchor(.homeContinueMemoir)
                tutorialCoordinator.clearAnchor(.homeYourBook)
                if tutorialCoordinator.visibleScreen == .home {
                    tutorialCoordinator.setVisibleScreen(.unknown)
                }
            }
            .onChange(of: profileVM.selectedProfile.id) { _ in
                fetchEntries()
            }
            .onReceive(NotificationCenter.default.publisher(for: .memorySaved)) { _ in
                fetchEntries()
            }
            .navigationDestination(isPresented: $navigateToMemoir) {
                MemoirView()
                    .environmentObject(profileVM)
                    .environmentObject(tutorialCoordinator)
            }
            .fullScreenCover(isPresented: $showMemoirPicker, onDismiss: {
                if pendingNavigateToMemoir {
                    navigateToMemoir = true
                    pendingNavigateToMemoir = false
                }
            }) {
                MemoirModePickerView(onSelect: { _ in
                    hasChosenMemoirMode = true
                    pendingNavigateToMemoir = true
                })
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .id(tutorialCoordinator.homeNavigationResetToken)
    }

    // MARK: – Data Fetching & Helpers
    
    /// Assigns only pre-profile legacy rows. Existing profile ownership is authoritative.
    private func migrateLegacyUnassignedMemories() {
        let context = PersistenceController.shared.container.viewContext
        let currentProfileID = profileVM.selectedProfile.id

        guard let uid = MemoryUserScope.currentFirebaseUserId else { return }

        let allRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        let predicates: [NSPredicate] = [
            NSPredicate(format: "profileID == nil"),
            NSPredicate(format: "firebaseUserId == %@", uid)
        ]
        allRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        guard let legacyMemories = try? context.fetch(allRequest), !legacyMemories.isEmpty else {
            return
        }

        for memory in legacyMemories {
            guard let recoveredProfileID = MemoryProfileRecoveryPolicy.recoveredProfileID(
                existingProfileID: memory.profileID,
                selectedProfileID: currentProfileID
            ) else {
                continue
            }
            memory.profileID = recoveredProfileID
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            print("❌ Failed to migrate legacy unassigned memories: \(error)")
        }
    }

    private func fetchEntries() {
        // Force refresh to get latest data from persistent store
        context.refreshAllObjects()
        
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileVM.selectedProfile.id)
        request.includesPendingChanges = true
        request.returnsObjectsAsFaults = false
        
        do {
            entries = try context.fetch(request)
            print("📊 Homepage fetched \(entries.count) entries for active profile")
            
            // Debug: log how many have chapters
            let withChapter = entries.filter { $0.chapter != nil && !($0.chapter?.isEmpty ?? true) }
            print("📊 Entries with chapter: \(withChapter.count)")
        } catch {
            print("Failed to fetch entries:", error)
        }
    }

    private func resetDailyPromptIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = UserDefaults.standard.object(forKey: "PromptCompletedDate") as? Date

        if lastDate == nil ||
           Calendar.current.compare(today, to: lastDate!, toGranularity: .day) != .orderedSame {
            UserDefaults.standard.set(false, forKey: promptOfTheDay)
            UserDefaults.standard.set(today, forKey: "PromptCompletedDate")
            
            // Backup to iCloud for persistence
            NSUbiquitousKeyValueStore.default.set(false, forKey: "memoir_\(promptOfTheDay)")
            NSUbiquitousKeyValueStore.default.set(today, forKey: "memoir_PromptCompletedDate")
            NSUbiquitousKeyValueStore.default.synchronize()
        }

        // Try local first, then iCloud backup
        var localCompleted = UserDefaults.standard.bool(forKey: promptOfTheDay)
        if !localCompleted {
            NSUbiquitousKeyValueStore.default.synchronize()
            localCompleted = NSUbiquitousKeyValueStore.default.bool(forKey: "memoir_\(promptOfTheDay)")
            if localCompleted {
                UserDefaults.standard.set(true, forKey: promptOfTheDay)
            }
        }
        
        promptCompleted = localCompleted
    }

    // Helper to build editor view lazily
    private func buildEditor() -> some View {
        let ctx = context
        let profID = profileVM.selectedProfile.id
        var pages: [EditorPage] = {
            let req: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            req.predicate = MemoryUserScope.profilePredicate(profileID: profID)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let mems = (try? ctx.fetch(req)) ?? []
            return EditorPage.pages(from: mems, context: ctx)
        }()

        // Insert cover page at front
        let coverKey = "coverSettings_\(profID.uuidString)"
        let cover: CoverSettings = {
            if let data = UserDefaults.standard.data(forKey: coverKey),
               let ct = try? JSONDecoder().decode(CoverSettings.self, from: data) {
                return ct
            }
            return CoverSettings(title: "Stories of My Life", subtitle: "", accentHex: "000000", coverPhotoData: nil)
        }()

        let coverPage = EditorPage(title: cover.title, body: "", photo: cover.coverPhotoData, memory: nil, context: ctx, isCover: true)
        pages.insert(coverPage, at: 0)
        return BookEditorPrototypeView(profileID: profID, pages: pages)
    }
}

struct HomepageView_Previews: PreviewProvider {
    static var previews: some View {
        HomepageView(openStorybook: {})
            .environmentObject(ProfileViewModel())
            .environmentObject(TutorialCoordinator.shared)
    }
}
