// HomepageView.swift
// MemoirAI

import SwiftUI
import PhotosUI
import CoreData

// Wrapper to allow Data to be used with .sheet(item:)
struct IdentifiableData: Identifiable {
    let id = UUID()
    let data: Data
}

struct HomepageView: View {
    // MARK: – Environment & Context
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    // MARK: – State
    @State private var selectedTab = 0
    let promptOfTheDay = "Tell me about your first job."
    @State private var promptCompleted: Bool = false

    @State private var entries: [MemoryEntry] = []
    private var totalChapters: Int { activeChapters.count }

    @State private var isShowingPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var selectedPhotoData: IdentifiableData? = nil

    @State private var disableCameraWiggle: Bool = {
        let localValue = UserDefaults.standard.bool(forKey: HomepageView.cameraWiggleDisabledKey)
        if !localValue {
            // Try iCloud backup
            NSUbiquitousKeyValueStore.default.synchronize()
            let cloudValue = NSUbiquitousKeyValueStore.default.bool(forKey: "memoir_\(HomepageView.cameraWiggleDisabledKey)")
            if cloudValue {
                UserDefaults.standard.set(true, forKey: HomepageView.cameraWiggleDisabledKey)
                return true
            }
        }
        return localValue
    }()
    private static let cameraWiggleDisabledKey = "cameraWiggleDisabledKey_v1"
    /// Set after the app has entered the background at least once (user “closed” the app).
    private static let hasBackgroundedOnceKey = "profileSwitchWiggleHasBackgroundedOnce_v1"

    @State private var showingAddProfile = false
    @State private var showProfileEdit = false
    @State private var showProfileSwitcher = false

    @State private var showMemoryRecoveryAlert = false
    @State private var recoveredMemoryCount = 0

    @State private var showMemoirPicker = false
    @State private var pendingNavigateToMemoir = false
    @State private var navigateToMemoir = false
    @AppStorage("hasChosenMemoirMode") private var hasChosenMemoirMode = false

    // Animation flag for glowing gradient around the Book Preview button
    @State private var animatePreviewGlow = false

    // MARK: – Computed Properties

    /// How many full chapters have been completed?
    private func completedChaptersCount() -> Int {
        activeChapters.filter { chapter in
            filledPromptSlotsForChapter(entries: entries, chapter: chapter) >= chapter.prompts.count
        }.count
    }

    /// The text to show under "Continue Your Memoir"
    private var progressText: String {
        let done = completedChaptersCount()
        if done == 0 {
            return "No chapters completed yet"
        } else {
            return "\(done) of \(totalChapters) chapters completed"
        }
    }
    
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
                            viewModel: profileVM,
                            disableWiggle: $disableCameraWiggle
                        ) {
                            showProfileSwitcher = true
                            if !disableCameraWiggle {
                                disableCameraWiggle = true
                                UserDefaults.standard.set(true, forKey: HomepageView.cameraWiggleDisabledKey)
                                
                                // Backup to iCloud for persistence
                                NSUbiquitousKeyValueStore.default.set(true, forKey: "memoir_\(HomepageView.cameraWiggleDisabledKey)")
                                NSUbiquitousKeyValueStore.default.synchronize()
                            }
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

                        // START RECORDING
                        NavigationLink(destination: RecordMemoryView()
                            .environmentObject(profileVM)
                            .environmentObject(tutorialCoordinator)) {
                            Text("Start Recording")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color(red: 0.83, green: 0.45, blue: 0.14))
                                )
                                .padding(.horizontal)
                                .shadow(color: Color.orange.opacity(0.25), radius: 6, x: 0, y: 3)
                        }

                        // CONTINUE YOUR MEMOIR
                        Button {
                            if hasChosenMemoirMode {
                                navigateToMemoir = true
                            } else {
                                showMemoirPicker = true
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Continue Your Memoir")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text(progressText)
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.7))
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("\(completionPercentage)%")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(Color(red: 0.98, green: 0.93, blue: 0.80))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
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

                        // RECORD MEMORIES
                        NavigationLink(destination: RecordMemoryView()
                            .environmentObject(profileVM)
                            .environmentObject(tutorialCoordinator)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Record Memories")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text("Share stories in your own voice")
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "mic.fill")
                                    .foregroundColor(Color(red: 0.83, green: 0.45, blue: 0.14))
                            }
                            .padding()
                            .background(Color(red: 0.98, green: 0.93, blue: 0.80))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                            .padding(.horizontal)
                        }
                        
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
                checkAndRecoverOrphanedMemories()
                fetchEntries()
                
                if !disableCameraWiggle,
                   UserDefaults.standard.bool(forKey: HomepageView.hasBackgroundedOnceKey) {
                    disableCameraWiggle = true
                    UserDefaults.standard.set(true, forKey: HomepageView.cameraWiggleDisabledKey)
                    NSUbiquitousKeyValueStore.default.set(true, forKey: "memoir_\(HomepageView.cameraWiggleDisabledKey)")
                    NSUbiquitousKeyValueStore.default.synchronize()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    UserDefaults.standard.set(true, forKey: HomepageView.hasBackgroundedOnceKey)
                }
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
            .photosPicker(isPresented: $isShowingPhotoPicker, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { newItem in
                if let newItem = newItem {
                    loadPhotoData(newItem)
                }
            }
            .sheet(item: $selectedPhotoData) { wrapper in
                CropSheetView(photoData: wrapper.data) { croppedData in
                    // profileVM.addProfile(...) as needed
                }
            }
            .fullScreenCover(isPresented: $showProfileEdit) {
                ProfileEditView(profileVM: profileVM)
            }
            .sheet(isPresented: $showProfileSwitcher) {
                ProfileSwitcherView()
                    .environmentObject(profileVM)
            }
            .alert("Memories Recovered!", isPresented: $showMemoryRecoveryAlert) {
                Button("Great!") {}
            } message: {
                Text("We found and recovered \(recoveredMemoryCount) of your memories that were previously missing.")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MemoriesRecovered"))) { notification in
                if let count = notification.object as? Int, count > 0 {
                    recoveredMemoryCount = count
                    showMemoryRecoveryAlert = true
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .id(tutorialCoordinator.homeNavigationResetToken)
    }

    // MARK: – Data Fetching & Helpers
    
    /// Check for orphaned memories (memories with profileID that doesn't match current profile)
    /// and reassign them to the current profile
    private func checkAndRecoverOrphanedMemories() {
        let context = PersistenceController.shared.container.viewContext
        let currentProfileID = profileVM.selectedProfile.id
        
        // Fetch ALL memories (no profileID filter)
        let allRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        if let uid = MemoryUserScope.currentFirebaseUserId {
            allRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "firebaseUserId == %@", uid),
                NSPredicate(format: "firebaseUserId == nil")
            ])
        }
        
        guard let allMemories = try? context.fetch(allRequest), !allMemories.isEmpty else {
            return // No memories at all
        }
        
        // Find memories that don't belong to current profile
        let orphanedMemories = allMemories.filter { $0.profileID != currentProfileID }
        
        if !orphanedMemories.isEmpty {
            print("🔍 Found \(orphanedMemories.count) orphaned memories. Reassigning to current profile...")
            
            // Reassign orphaned memories to current profile
            for memory in orphanedMemories {
                memory.profileID = currentProfileID
                if memory.firebaseUserId == nil {
                    memory.firebaseUserId = MemoryUserScope.currentFirebaseUserId
                }
            }
            
            do {
                try context.save()
                print("✅ Successfully reassigned \(orphanedMemories.count) memories to profile \(currentProfileID.uuidString)")
                
                // Show recovery alert
                recoveredMemoryCount = orphanedMemories.count
                showMemoryRecoveryAlert = true
                
                // Refresh entries
                fetchEntries()
            } catch {
                print("❌ Failed to save recovered memories: \(error)")
            }
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
            print("📊 Homepage fetched \(entries.count) entries for profile \(profileVM.selectedProfile.name)")
            
            // Debug: log how many have chapters
            let withChapter = entries.filter { $0.chapter != nil && !($0.chapter?.isEmpty ?? true) }
            print("📊 Entries with chapter: \(withChapter.count)")
        } catch {
            print("Failed to fetch entries:", error)
        }
    }

    private func loadPhotoData(_ newItem: PhotosPickerItem) {
        Task {
            do {
                if let data = try await newItem.loadTransferable(type: Data.self) {
                    selectedPhotoData = IdentifiableData(data: data)
                }
            } catch {
                print("Failed to load data:", error)
            }
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
