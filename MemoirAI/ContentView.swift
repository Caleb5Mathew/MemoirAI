import SwiftUI
import FBSDKCoreKit
import FirebaseAuth
import CoreData

struct ContentView: View {
    @EnvironmentObject var iCloudManager: iCloudManager
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    
    // Firebase Authentication
    @StateObject private var authService = AuthenticationService.shared
    
    // For deep-linking to memory details
    @StateObject private var nav = NavigationRouter.shared
    @State private var path = NavigationPath()
    
    // Local fallback for immediate availability even before iCloud sync
    @AppStorage("hasCompletedOnboarding_local") private var localCompleted: Bool = false
    
    // Store pending deep link if user scans QR code before completing onboarding
    @State private var pendingDeepLinkID: UUID? = nil
    @State private var showDeepLinkError = false
    @State private var deepLinkErrorMessage = ""
    
    var body: some View {
        #if targetEnvironment(simulator)
        let done = true
        #else
        let done = localCompleted || iCloudManager.hasCompletedOnboarding
        #endif
        
        return Group {
            if done {
                NavigationStack(path: $path) {
                    MainTabView(path: $path)
                    .toolbar(.hidden, for: .navigationBar)
                    .onReceive(nav.$selectedMemoryID.compactMap { $0 }) { id in
                        path.append(id)
                    }
                    .onChange(of: path) {
                        if path.isEmpty { nav.clear() }
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
                .environmentObject(nav)
                .task {
                    await routeToActiveCloudStorybookIfNeeded()
                }
                .onChange(of: profileVM.selectedProfile.id) { _, _ in
                    Task { await routeToActiveCloudStorybookIfNeeded() }
                }
                .onAppear {
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
        }
        // 🔗 DEEP LINK HANDLER: Catch QR code scans
        .onOpenURL { url in
            handleDeepLink(url)
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
    private func handleDeepLink(_ url: URL) {
        print("🔗 Deep link received: \(url.absoluteString)")
        
        // Parse the URL
        guard url.scheme == "memoirai" else {
            print("❌ Invalid URL scheme: \(url.scheme ?? "none")")
            return
        }
        
        guard url.host == "memory" else {
            print("❌ Invalid URL host: \(url.host ?? "none")")
            return
        }
        
        // Extract UUID from path (format: /UUID)
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let memoryID = UUID(uuidString: path) else {
            print("❌ Invalid UUID in path: \(path)")
            deepLinkErrorMessage = "Invalid memory link format."
            showDeepLinkError = true
            return
        }
        
        print("✅ Parsed memory ID: \(memoryID.uuidString)")
        
        // Check if onboarding is complete
        let done = localCompleted || iCloudManager.hasCompletedOnboarding
        
        if done {
            // User has completed onboarding - navigate immediately
            print("🔗 Navigating to memory: \(memoryID.uuidString)")
            
            // Verify memory exists before navigating
            if PersistenceController.shared.entry(id: memoryID) != nil {
                nav.showMemoryDetail(id: memoryID)
            } else {
                print("❌ Memory not found: \(memoryID.uuidString)")
                deepLinkErrorMessage = "This memory could not be found. It may belong to a different account or may have been deleted."
                showDeepLinkError = true
            }
        } else {
            // User hasn't completed onboarding - queue the deep link
            print("⏳ Onboarding incomplete - queuing deep link: \(memoryID.uuidString)")
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
            path = NavigationPath()
            path.append(StorybookRootRoute.resumeInProgressGeneration)
        }
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
