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
    @State private var finishedDebugOnboarding = false
    
    // Local fallback for immediate availability even before iCloud sync
    @AppStorage("hasCompletedOnboarding_local") private var localCompleted: Bool = false
    @AppStorage(CheckoutReturnPolicy.confirmedSessionDefaultsKey) private var confirmedCheckoutSessionID = ""

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
        let done = OnboardingDebugConfiguration.previewApp || (OnboardingDebugConfiguration.replayOnLaunch
            ? finishedDebugOnboarding
            : (localCompleted || iCloudManager.hasCompletedOnboarding))
        let seenWelcomeAuth = OnboardingDebugConfiguration.previewApp || OnboardingDebugConfiguration.replayOnLaunch || hasSeenWelcomeAuth

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
                    .navigationDestination(for: StorybookRootRoute.self) { route in
                        StoryPage()
                            .environmentObject(profileVM)
                            .environmentObject(tutorialCoordinator)
                            .environment(
                                \.storybookScreenEntry,
                                route == .resumeInProgressGeneration ? .autoResumePendingGeneration : .standard
                            )
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
                    GlobalStorybookProgressBanner(isNavigationRoot: path.isEmpty)
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
                        Task { await RCSubscriptionManager.shared.refreshCustomerInfo(forceRefresh: true) }
                        Task { await routeToActiveCloudStorybookIfNeeded() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .tutorialDismissToHome)) { _ in
                    path = NavigationPath()
                }
                .onAppear {
                    syncStorybookJobObserverBinding()
                    // Handle any pending deep link after onboarding completes
                    if let pendingID = pendingDeepLinkID {
                        print("🔗 Processing pending deep link: \(pendingID.uuidString.prefix(8))…")
                        pendingDeepLinkID = nil
                        Task {
                            guard await authService.prepareAuthenticatedSessionForLaunch() else { return }
                            await routeParsedMemory(memoryID: pendingID, source: "pendingOnboarding")
                        }
                    }
                    
                    // Auto sign-in anonymously and trigger migration
                    Task {
                        guard await authService.prepareAuthenticatedSessionForLaunch() else { return }
                        if let userID = MemoryUserScope.currentFirebaseUserId {
                            await profileVM.activateUser(userID)
                        }
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
                OnboardingFlow(onFinished: { finishedDebugOnboarding = true })
            }
        }
        .id(authService.user?.uid ?? "signed-out")
        .onChange(of: scenePhase, initial: true) { _, phase in
            ProductAnalytics.shared.setScreenTrackingActive(phase == .active)
            if phase == .active {
                ProductAnalytics.shared.setSessionActive(true)
            } else if phase == .background {
                ProductAnalytics.shared.setSessionActive(false)
            }
        }
        .onChange(of: authService.user?.uid) { oldUserID, newUserID in
            guard oldUserID != newUserID else { return }
            path = NavigationPath()
            nav.clear()
            syncStorybookJobObserverBinding()
            guard newUserID != nil else { return }
            Task {
                guard await authService.prepareAuthenticatedSessionForLaunch(),
                      let finalUserID = MemoryUserScope.currentFirebaseUserId else { return }
                await profileVM.activateUser(finalUserID)
                await FirestoreSyncService.shared.hydrateMemoriesFromFirestoreIfStoreEmpty(
                    context: PersistenceController.shared.container.viewContext
                )
            }
        }
        .onAppear {
            #if targetEnvironment(simulator)
            FreePreviewConfig.applySimulatorStaleDataCleanupIfNeeded()
            #endif
            // CRITICAL: Establish link between ad clicks and app opens
            AppEvents.shared.activateApp()

            // Resolve guest recovery before WelcomeAuthView can link credentials or any
            // profile store can activate under a temporary reinstall UID.
            Task {
                await authService.prepareAuthenticatedSessionForLaunch()
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
        .overlay(alignment: .top) {
            if !confirmedCheckoutSessionID.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Order confirmed")
                            .font(.headline)
                        Text("Follow printing and delivery in My Orders.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Done") { confirmedCheckoutSessionID = "" }
                        .font(.subheadline.weight(.semibold))
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityElement(children: .contain)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .orderComplete)) { notification in
            guard let sessionID = notification.userInfo?["sessionId"] as? String else { return }
            confirmedCheckoutSessionID = sessionID
        }
    }
    
    // MARK: - Deep Link Handling
    
    /// Handles incoming URLs from QR code scans.
    /// Accepts `memoirai://memory/{UUID}` (legacy printed books) and
    /// `https://memoirai-7db06.web.app/memory/{UUID}` (universal links in new books).
    private func handleDeepLink(_ url: URL, source: String) {
        print("[QRDeepLink] received memory link source=\(source)")

        guard MemoryLinks.looksLikeMemoryLink(url) else {
            // Not a memory link (Google/Facebook auth callbacks etc.) — not ours to handle.
            print("[QRDeepLink] ignore non-memory url source=\(source)")
            return
        }
        guard let memoryID = MemoryLinks.parseMemoryDeepLink(url) else {
            print("[QRDeepLink] rejected invalid memory link source=\(source)")
            deepLinkErrorMessage = "Invalid memory link format."
            showDeepLinkError = true
            return
        }

        lastDeepLinkAt = Date()
        print("✅ Parsed memory ID: \(memoryID.uuidString.prefix(8))…")

        // Check if onboarding is complete
        let done = localCompleted || iCloudManager.hasCompletedOnboarding

        if done {
            Task { await routeParsedMemory(memoryID: memoryID, source: source) }
        } else {
            // User hasn't completed onboarding - queue the deep link
            print("[QRDeepLink] queued pending onboarding memoryID=\(memoryID.uuidString.prefix(8))… source=\(source)")
            pendingDeepLinkID = memoryID
            deepLinkErrorMessage = "Please complete the setup to view this memory."
            showDeepLinkError = true
        }
    }

    private func routeParsedMemory(memoryID: UUID, source: String) async {
        let found = PersistenceController.shared.entry(id: memoryID) != nil
        print("[QRDeepLink] memoryID=\(memoryID.uuidString.prefix(8))… entryFound=\(found) source=\(source)")
        if found {
            print("[QRDeepLink] navWillPush=true source=\(source)")
            nav.showMemoryDetail(id: memoryID)
            return
        }
        print("[QRDeepLink] memory not in store — resolving owner source=\(source)")
        await routeNonLocalMemory(memoryID: memoryID, source: source)
    }

    /// A scanned memory that is not in the local store: resolve its owner via the
    /// server-maintained memoryIndex and push the shared memory flow, which handles
    /// both "mine but not hydrated" and "someone else's, request access."
    private func routeNonLocalMemory(memoryID: UUID, source: String) async {
        do {
            guard let ownerId = try await SharedAccessService.shared.resolveOwner(memoryId: memoryID) else {
                print("[QRDeepLink] owner not resolved memoryID=\(memoryID.uuidString.prefix(8))… source=\(source)")
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
        
        guard let uid = MemoryUserScope.currentFirebaseUserId else { return }
        request.predicate = NSPredicate(format: "firebaseUserId == %@", uid)
        
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
        
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.synchronize()
        let claimedOwnerID = MemoryOwnershipPolicy.resolvedLegacyOwnerID(
            localOwnerID: UserDefaults.standard.string(forKey: MemoryOwnershipPolicy.legacyOwnerKey),
            cloudOwnerID: cloudStore.string(forKey: MemoryOwnershipPolicy.cloudLegacyOwnerKey)
        )
        guard MemoryOwnershipPolicy.canClaimLegacyRows(
            claimedOwnerID: claimedOwnerID,
            currentUserID: uid,
            deletionBarrierActive: AccountCloudDataPolicy.isDeletionBarrierActive(
                userID: uid,
                cloudStore: cloudStore
            )
        ) else {
            print("⚠️ Skipping local ownership backfill - legacy rows belong to another account")
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
            
            UserDefaults.standard.set(uid, forKey: MemoryOwnershipPolicy.legacyOwnerKey)
            cloudStore.set(uid, forKey: MemoryOwnershipPolicy.cloudLegacyOwnerKey)
            cloudStore.synchronize()
            print("✅ Local ownership backfill complete for UID \(uid.prefix(8))…: \(legacyRows.count) rows updated")
        } catch {
            print("❌ Local ownership backfill failed for UID \(uid.prefix(8))…: \(error)")
        }
    }

    /// Aggressive auto-resume: if a cloud storybook job is in progress — or finished while the
    /// user was away and they haven't seen the result — reset navigation to root and open `StoryPage`.
    /// Seen-gating makes this fire at most once per generation per app-open; `force` (banner tap)
    /// bypasses the gating but still no-ops when `StoryPage` is already on screen.
    private func routeToActiveCloudStorybookIfNeeded(force: Bool = false) async {
        guard authService.isSignedIn else { return }
        let requestedProfileID = profileVM.selectedProfile.id
        let requestedUserID = Auth.auth().currentUser?.uid
        let navigationRevision = StorybookSeenTracker.shared.navigationRevision
        guard let job = await fetchRoutableStorybookJobWithRetry(profileId: requestedProfileID) else {
            return
        }
        await MainActor.run {
            let tracker = StorybookSeenTracker.shared
            guard tracker.navigationRevision == navigationRevision,
                  profileVM.selectedProfile.id == requestedProfileID,
                  authService.isSignedIn,
                  Auth.auth().currentUser?.uid == requestedUserID else { return }
            if tracker.isStoryPageVisible || tracker.isStoryPageNavigationPending { return }
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
            var destinationPath = NavigationPath()
            destinationPath.append(StorybookRootRoute.resumeInProgressGeneration)
            path = destinationPath
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
