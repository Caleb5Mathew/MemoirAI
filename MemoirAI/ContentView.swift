import SwiftUI
import FBSDKCoreKit
import FirebaseAuth
import CoreData
import Combine

struct ContentView: View {
    @EnvironmentObject var iCloudManager: iCloudManager
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @Environment(\.scenePhase) private var scenePhase
    
    // Firebase Authentication
    @StateObject private var authService = AuthenticationService.shared
    
    // For deep-linking to memory details
    @StateObject private var nav = NavigationRouter.shared
    @State private var path = NavigationPath()
    
    // Local fallback for immediate availability even before iCloud sync
    @AppStorage("hasCompletedOnboarding_local") private var localCompleted: Bool = false

    // Shown exactly once, on first launch, before onboarding. UserDefaults-only (not mirrored
    // to iCloud KV): iCloudManager's KV sync semantics are onboarding-specific (see its
    // "never flip false→true mid-session" guard) and reusing that same key/logic for an
    // unrelated flag would risk subtly changing onboarding's own sync behavior. A fresh
    // install on a second device will see this screen again, which is an acceptable tradeoff
    // for a one-time welcome screen.
    @AppStorage("hasSeenWelcomeAuth") private var hasSeenWelcomeAuth: Bool = false

    // Store pending deep link if user scans QR code before completing onboarding
    @State private var pendingDeepLinkID: UUID? = nil
    @State private var showDeepLinkError = false
    @State private var deepLinkErrorMessage = ""

    /// Set when a `memoirai://memory/{UUID}` URL parses successfully; used to avoid storybook auto-resume clobbering the push.
    @State private var lastDeepLinkAt: Date?
    /// True while `routeToActiveCloudStorybookIfNeeded` is resetting `path` so `.onChange(of: path)` does not call `nav.clear()` on the transient empty stack.
    @State private var programmaticNavigationReset = false
    
    var body: some View {
        #if targetEnvironment(simulator)
        let done = true
        let seenWelcomeAuth = true
        #else
        let done = localCompleted || iCloudManager.hasCompletedOnboarding
        let seenWelcomeAuth = hasSeenWelcomeAuth
        #endif

        return Group {
            if !seenWelcomeAuth {
                WelcomeAuthView(onFinished: { hasSeenWelcomeAuth = true })
            } else if done {
                NavigationStack(path: $path) {
                    MainTabView(path: $path)
                    .toolbar(.hidden, for: .navigationBar)
                    .onReceive(nav.$selectedMemoryID.compactMap { $0 }.removeDuplicates()) { id in
                        path.append(id)
                    }
                    .onChange(of: path) { oldPath, newPath in
                        guard newPath.isEmpty, !oldPath.isEmpty else { return }
                        if programmaticNavigationReset { return }
                        nav.clear()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        Task { await routeToActiveCloudStorybookIfNeeded() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .navigateToCloudStorybookGeneration)) { _ in
                        Task { await routeToActiveCloudStorybookIfNeeded() }
                    }
                    .navigationDestination(for: StorybookRootRoute.self) { _ in
                        StoryPage()
                            .environmentObject(profileVM)
                            .environmentObject(tutorialCoordinator)
                            .environment(\.storybookScreenEntry, .autoResumePendingGeneration)
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let entry = PersistenceController.shared.entry(id: id) {
                            MemoryDetailView(memory: entry)
                                .environmentObject(profileVM)
                                .onDisappear { nav.clear() }
                        } else {
                            Text("Memory not found").font(.headline)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    GlobalStorybookProgressBanner()
                }
                .environmentObject(nav)
                .task {
                    syncStorybookJobObserverBinding()
                    await routeToActiveCloudStorybookIfNeeded()
                }
                .onChange(of: profileVM.selectedProfile.id) { _, _ in
                    syncStorybookJobObserverBinding()
                    Task { await routeToActiveCloudStorybookIfNeeded() }
                }
                .onChange(of: authService.isSignedIn) { _, _ in
                    syncStorybookJobObserverBinding()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await routeToActiveCloudStorybookIfNeeded() }
                    }
                }
                .onAppear {
                    syncStorybookJobObserverBinding()
                    // Handle any pending deep link after onboarding completes
                    if let pendingID = pendingDeepLinkID {
                        print("🔗 Processing pending deep link: \(pendingID.uuidString)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            nav.showMemoryDetail(id: pendingID)
                            pendingDeepLinkID = nil
                        }
                    }
                    
                    // Auto sign-in anonymously and trigger migration
                    Task {
                        await authService.signInAnonymouslyIfNeeded()
                        await backfillLocalMemoryOwnershipIfNeeded()

                        await FirestoreSyncService.shared.hydrateMemoriesFromFirestoreIfStoreEmpty(
                            context: PersistenceController.shared.container.viewContext
                        )

                        // Trigger migration after sign-in (includes memories restored from Firestore hydrate)
                        if authService.isSignedIn && !FirestoreSyncService.shared.isMigrationComplete {
                            triggerFirebaseMigration()
                        }

                        // Push profile name to user doc so admin can identify users
                        if let name = profileVM.profiles.first?.name, !name.isEmpty {
                            await authService.updateProfileNameInUserDoc(name)
                        }

                        await MainActor.run {
                            syncStorybookJobObserverBinding()
                        }
                    }
                }
            } else {
                OnboardingFlow()
            }
        }
        .onAppear {
            #if targetEnvironment(simulator)
            FreePreviewConfig.applySimulatorStaleDataCleanupIfNeeded()
            #endif
            // CRITICAL: Establish link between ad clicks and app opens
            AppEvents.shared.activateApp()

            // Anonymous sign-in must exist *before* WelcomeAuthView can offer to link an
            // Apple/Google/email credential to it. Previously this only ran inside the
            // post-onboarding branch below; `signInAnonymouslyIfNeeded()` is a no-op once
            // already signed in, so calling it here too is safe and idempotent.
            Task {
                await authService.signInAnonymouslyIfNeeded()
            }
        }
        // 🔗 DEEP LINK HANDLER: Catch QR code scans
        .onOpenURL { url in
            handleDeepLink(url, source: "onOpenURL")
        }
        .onReceive(NotificationCenter.default.publisher(for: .memoirOpenMemoryDeepLink)) { note in
            if let url = note.userInfo?["url"] as? URL {
                handleDeepLink(url, source: "AppDelegateNotification")
            }
        }
        .alert("Unable to Open Memory", isPresented: $showDeepLinkError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deepLinkErrorMessage)
        }
    }
    
    // MARK: - Deep Link Handling
    
    /// Handles incoming URLs from QR code scans
    /// Expected format: memoirai://memory/{UUID}
    private func handleDeepLink(_ url: URL, source: String) {
        print("[QRDeepLink] received url=\(url.absoluteString) source=\(source)")
        print("🔗 Deep link received: \(url.absoluteString)")
        
        // Parse the URL
        guard url.scheme == "memoirai" else {
            print("[QRDeepLink] reject scheme=\(url.scheme ?? "none") source=\(source)")
            print("❌ Invalid URL scheme: \(url.scheme ?? "none")")
            return
        }
        
        guard url.host == "memory" else {
            print("[QRDeepLink] reject host=\(url.host ?? "none") source=\(source)")
            print("❌ Invalid URL host: \(url.host ?? "none")")
            return
        }
        
        // Extract UUID from path (format: /UUID)
        let idSegment = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let memoryID = UUID(uuidString: idSegment) else {
            print("[QRDeepLink] reject invalidUUID segment=\(idSegment) source=\(source)")
            print("❌ Invalid UUID in path: \(idSegment)")
            deepLinkErrorMessage = "Invalid memory link format."
            showDeepLinkError = true
            return
        }

        lastDeepLinkAt = Date()
        
        print("✅ Parsed memory ID: \(memoryID.uuidString)")
        
        // Check if onboarding is complete
        let done = localCompleted || iCloudManager.hasCompletedOnboarding
        
        if done {
            // User has completed onboarding - navigate immediately
            print("🔗 Navigating to memory: \(memoryID.uuidString)")
            
            // Verify memory exists before navigating
            let entry = PersistenceController.shared.entry(id: memoryID)
            let found = entry != nil
            print("[QRDeepLink] memoryID=\(memoryID.uuidString) entryFound=\(found) source=\(source)")
            if found {
                print("[QRDeepLink] navWillPush=true source=\(source)")
                nav.showMemoryDetail(id: memoryID)
            } else {
                print("[QRDeepLink] memory not in store — showing alert source=\(source)")
                print("❌ Memory not found: \(memoryID.uuidString)")
                deepLinkErrorMessage = "This memory could not be found. It may belong to a different account or may have been deleted."
                showDeepLinkError = true
            }
        } else {
            // User hasn't completed onboarding - queue the deep link
            print("⏳ Onboarding incomplete - queuing deep link: \(memoryID.uuidString)")
            print("[QRDeepLink] queued pending onboarding memoryID=\(memoryID.uuidString) source=\(source)")
            pendingDeepLinkID = memoryID
            deepLinkErrorMessage = "Please complete the setup to view this memory."
            showDeepLinkError = true
        }
    }
    
    // MARK: - Firebase Migration
    
    /// Trigger one-time migration of existing Core Data memories to Firebase
    private func triggerFirebaseMigration() {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: true)]
        
        if let uid = MemoryUserScope.currentFirebaseUserId {
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "firebaseUserId == %@", uid),
                NSPredicate(format: "firebaseUserId == nil")
            ])
        }
        
        do {
            let memories = try context.fetch(request)
            if !memories.isEmpty {
                print("📤 Starting Firebase migration for \(memories.count) memories...")
                Task {
                    await FirestoreSyncService.shared.migrateExistingMemories(memories)
                }
            }
        } catch {
            print("❌ Failed to fetch memories for migration: \(error)")
        }
    }

    private func backfillLocalMemoryOwnershipIfNeeded() async {
        guard let uid = MemoryUserScope.currentFirebaseUserId else {
            print("⚠️ Skipping local ownership backfill - no Firebase UID")
            return
        }
        
        let key = "local_memory_uid_backfill_\(uid)"
        if UserDefaults.standard.bool(forKey: key) {
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "firebaseUserId == nil")
        
        do {
            let legacyRows = try context.fetch(request)
            if !legacyRows.isEmpty {
                for memory in legacyRows {
                    memory.firebaseUserId = uid
                }
                try context.save()
            }
            
            UserDefaults.standard.set(true, forKey: key)
            print("✅ Local ownership backfill complete for UID \(uid): \(legacyRows.count) rows updated")
        } catch {
            print("❌ Local ownership backfill failed for UID \(uid): \(error)")
        }
    }

    /// Aggressive auto-resume: if a cloud storybook job is in progress, reset navigation to root and open `StoryPage`.
    private func routeToActiveCloudStorybookIfNeeded() async {
        guard authService.isSignedIn else { return }
        guard (try? await FirestoreSyncService.shared.fetchLatestActiveStorybookJob(profileId: profileVM.selectedProfile.id)) != nil else {
            return
        }
        await MainActor.run {
            if let t = lastDeepLinkAt, Date().timeIntervalSince(t) < 3, nav.selectedMemoryID != nil {
                print("[QRDeepLink] routeToActive skipped — recent deep link at \(t) (preserving memory navigation)")
                return
            }
            print("[QRDeepLink] routeToActive applying — active storybook job")
            programmaticNavigationReset = true
            nav.clear()
            path = NavigationPath()
            path.append(StorybookRootRoute.resumeInProgressGeneration)
            DispatchQueue.main.async {
                programmaticNavigationReset = false
            }
        }
    }

    private func syncStorybookJobObserverBinding() {
        ActiveStorybookJobObserver.shared.bind(
            profileID: profileVM.selectedProfile.id,
            isSignedIn: authService.isSignedIn
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(iCloudManager.shared)
            .environmentObject(ProfileViewModel())
            .environmentObject(TutorialCoordinator.shared)
    }
}
