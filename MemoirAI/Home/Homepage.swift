// HomepageView.swift
// MemoirAI

import SwiftUI
import CoreData

struct HomepageView: View {
    // MARK: – Environment & Context
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @Environment(\.managedObjectContext) private var context

    // MARK: – State
    @State private var selectedTab = 0
    let promptOfTheDay = "Tell me about your first job."
    @State private var promptCompleted: Bool = false

    @State private var entries: [MemoryEntry] = []

    @State private var showingAddProfile = false
    @State private var showProfileEdit = false
    @State private var showProfileSwitcher = false

    @State private var showMemoirPicker = false
    @State private var pendingNavigateToMemoir = false
    @State private var navigateToMemoir = false
    @AppStorage("hasChosenMemoirMode") private var hasChosenMemoirMode = false

    // Animation flag for glowing gradient around the Book Preview button
    @State private var animatePreviewGlow = false

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
        NavigationStack {
            VStack(spacing: 0) {
                // ─── TOP BAR ─────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memoir")
                            .font(.customSerifFallback(size: 22))
                            .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))

                        if !profileVM.profiles.isEmpty && !profileVM.selectedProfile.name.isEmpty {
                            Text("Hello, \(profileVM.selectedProfile.name)")
                                .font(.subheadline)
                                .foregroundColor(.black.opacity(0.7))
                        }
                    }
                    Spacer()
                    
                    // Profile Icon Button
                    Button {
                        showProfileEdit = true
                    } label: {
                        ProfileIconView(profile: profileVM.selectedProfile)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Profile Photo + Title
                        ProfilePhotoView(
                            viewModel: profileVM
                        ) {
                            showProfileSwitcher = true
                        }

                        VStack(spacing: 10) {
                            Text("Your voice.\nYour legacy.")
                                .font(.customSerifFallback(size: 30))
                                .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))
                                .multilineTextAlignment(.center)

                            Text("Capture your stories for future generations. No typing, just talking.")
                                .font(.subheadline)
                                .foregroundColor(Color.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // CONTINUE YOUR MEMORIES
                        Button {
                            if hasChosenMemoirMode {
                                navigateToMemoir = true
                            } else {
                                showMemoirPicker = true
                            }
                        } label: {
                            HStack {
                                Text("Continue Your Memories")
                                    .font(.system(size: 18, weight: .semibold))
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("\(completionPercentage)%")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color(red: 0.83, green: 0.45, blue: 0.14))
                            )
                            .shadow(color: Color.orange.opacity(0.25), radius: 6, x: 0, y: 3)
                            .padding(.horizontal)
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
                        
                        // YOUR BOOK (Premium Gradient Outline)
                        NavigationLink(destination: StoryPage()
                            .environmentObject(profileVM)
                            .environmentObject(tutorialCoordinator)
                        ) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your Book")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text("Generate your life story here!")
                                        .font(.footnote)
                                        .foregroundColor(.black.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 0.98, green: 0.93, blue: 0.80))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                AngularGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.orange,
                                                        Color.yellow,
                                                        Color.red.opacity(0.8),
                                                        Color.orange
                                                    ]),
                                                    center: .center,
                                                    angle: .degrees(animatePreviewGlow ? 360 : 0)
                                                ),
                                                lineWidth: 3
                                            )
                                    )
                            )
                            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                            .padding(.horizontal)
                            .onAppear {
                                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                                    animatePreviewGlow = true
                                }
                            }
                        }
                        .tutorialAnchor(.homeYourBook)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { tutorialCoordinator.reportAnchor(.homeYourBook, rect: geo.frame(in: .global)) }
                                    .onChange(of: geo.frame(in: .global)) { _, f in tutorialCoordinator.reportAnchor(.homeYourBook, rect: f) }
                            }
                        )
                        .accessibilityIdentifier("tutorialYourBook")

                        // Clears the floating tab bar so the last card is fully visible
                        // and tappable when scrolled to the bottom.
                        Spacer(minLength: 110)
                    }
                    .padding(.top, 24)
                }
            }
            .background(Color(red: 0.98, green: 0.94, blue: 0.86).ignoresSafeArea(.all))
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
            .sheet(isPresented: $showingAddProfile) {
                AddProfileView()
                    .environmentObject(profileVM)
            }
            .fullScreenCover(isPresented: $showProfileEdit) {
                ProfileEditView(profileVM: profileVM)
            }
            .sheet(isPresented: $showProfileSwitcher) {
                ProfileSwitcherView()
                    .environmentObject(profileVM)
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
        HomepageView()
            .environmentObject(ProfileViewModel())
            .environmentObject(TutorialCoordinator.shared)
    }
}
