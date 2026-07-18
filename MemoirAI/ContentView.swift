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
                    .onReceive(nav.$sharedMemoryRoute.compactMap { $0 }.removeDuplicates()) { route in
                        path.append(route)
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
                        Task { await routeToActiveCloudStorybookIfNeeded(force: true) }
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
                    .navigationDestination(for: SharedMemoryRoute.self) { route in
                        SharedMemoryFlowView(route: route)
                            .onDisappear { nav.clear() }
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
                .onChange(of: authService.isSignedIn) { _, isSignedIn in
                    syncStorybookJobObserverBinding()
                    // Cold launch: the .task routing attempt runs before Firebase Auth restores
                    // the session and bails on the isSignedIn guard — retry once auth is back.
                    if isSignedIn {
                        Task { await routeToActiveCloudStorybookIfNeeded() }
                    }
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
    
    /// Handles incoming URLs from QR code scans.
    /// Accepts `memoirai://memory/{UUID}` (legacy printed books) and
    /// `https://memoirai-7db06.web.app/memory/{UUID}` (universal links in new books).
    private func handleDeepLink(_ url: URL, source: String) {
        print("[QRDeepLink] received url=\(url.absoluteString) source=\(source)")

        guard MemoryLinks.looksLikeMemoryLink(url) else {
            // Not a memory link (Google/Facebook auth callbacks etc.) — not ours to handle.
            print("[QRDeepLink] ignore non-memory url source=\(source)")
            return
        }
        guard let memoryID = MemoryLinks.parseMemoryDeepLink(url) else {
            print("[QRDeepLink] reject invalidUUID url=\(url.absoluteString) source=\(source)")
            deepLinkErrorMessage = "Invalid memory link format."
            showDeepLinkError = true
            return
        }

        lastDeepLinkAt = Date()
        print("✅ Parsed memory ID: \(memoryID.uuidString)")

        // Check if onboarding is complete
        let done = localCompleted || iCloudManager.hasCompletedOnboarding

        if done {
            // Verify memory exists before navigating
            let entry = PersistenceController.shared.entry(id: memoryID)
            let found = entry != nil
            print("[QRDeepLink] memoryID=\(memoryID.uuidString) entryFound=\(found) source=\(source)")
            if found {
                print("[QRDeepLink] navWillPush=true source=\(source)")
                nav.showMemoryDetail(id: memoryID)
            } else {
                // Not in the local store: could be someone else's memory (shared scan) or an
                // own memory that has not hydrated yet. Resolve the owner and route.
                print("[QRDeepLink] memory not in store — resolving owner source=\(source)")
                Task { await routeNonLocalMemory(memoryID: memoryID, source: source) }
            }
        } else {
            // User hasn't completed onboarding - queue the deep link
            print("[QRDeepLink] queued pending onboarding memoryID=\(memoryID.uuidString) source=\(source)")
            pendingDeepLinkID = memoryID
            deepLinkErrorMessage = "Please complete the setup to view this memory."
            showDeepLinkError = true
        }
    }

    /// A scanned memory that is not in the local store: resolve its owner via the
    /// server-maintained memoryIndex and push the shared memory flow, which handles
    /// both "mine but not hydrated" and "someone else's, request access."
    private func routeNonLocalMemory(memoryID: UUID, source: String) async {
        do {
            guard let ownerId = try await SharedAccessService.shared.resolveOwner(memoryId: memoryID) else {
                print("[QRDeepLink] owner not resolved memoryID=\(memoryID.uuidString) source=\(source)")
                await MainActor.run {
                    deepLinkErrorMessage = "This memory could not be found. It may have been deleted."
                    showDeepLinkError = true
                }
                return
            }
            await MainActor.run {
                nav.showSharedMemory(ownerId: ownerId, memoryId: memoryID)
            }
        } catch {
            print("[QRDeepLink] owner resolution failed: \(error.localizedDescription) source=\(source)")
            await MainActor.run {
                deepLinkErrorMessage = "Could not load this memory. Check your connection and try again."
                showDeepLinkError = true
            }
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

    /// Aggressive auto-resume: if a cloud storybook job is in progress — or finished while the
    /// user was away and they haven't seen the result — reset navigation to root and open `StoryPage`.
    /// Seen-gating makes this fire at most once per generation per app-open; `force` (banner tap)
    /// bypasses the gating but still no-ops when `StoryPage` is already on screen.
    private func routeToActiveCloudStorybookIfNeeded(force: Bool = false) async {
        guard authService.isSignedIn else { return }
        guard let job = await fetchRoutableStorybookJobWithRetry(profileId: profileVM.selectedProfile.id) else {
            return
        }
        await MainActor.run {
            let tracker = StorybookSeenTracker.shared
            if tracker.isStoryPageVisible { return }
            if !force {
                if job.status == "complete" {
                    guard !tracker.hasSeenCompleted(jobId: job.jobId) else { return }
                } else {
                    guard !tracker.hasSeenThisForeground(jobId: job.jobId) else { return }
                }
            }
            if let t = lastDeepLinkAt, Date().timeIntervalSince(t) < 3, nav.selectedMemoryID != nil {
                print("[QRDeepLink] routeToActive skipped — recent deep link at \(t) (preserving memory navigation)")
                return
            }
            print("[QRDeepLink] routeToActive applying — storybook job \(job.jobId.prefix(24))… status=\(job.status)")
            tracker.notePendingRoute(jobId: job.jobId, isComplete: job.status == "complete")
            programmaticNavigationReset = true
            nav.clear()
            path = NavigationPath()
            path.append(StorybookRootRoute.resumeInProgressGeneration)
            DispatchQueue.main.async {
                programmaticNavigationReset = false
            }
        }
    }

    /// Cold launch can race Firestore's connection; a transient fetch error must not be
    /// mistaken for "no job to resume" (that is exactly the bug that stranded users on Home).
    private func fetchRoutableStorybookJobWithRetry(
        profileId: UUID,
        attempts: Int = 3
    ) async -> FirestoreSyncService.ActiveStorybookCloudJob? {
        for attempt in 1...attempts {
            do {
                return try await FirestoreSyncService.shared.fetchLatestRoutableStorybookJob(profileId: profileId)
            } catch {
                print("⚠️ routeToActive fetch attempt \(attempt)/\(attempts) failed: \(error.localizedDescription)")
                if attempt < attempts {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
            }
        }
        return nil
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
