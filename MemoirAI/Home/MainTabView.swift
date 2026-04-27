import SwiftUI
import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore

struct MainTabView: View {
    @Binding var path: NavigationPath
    @AppStorage("memoirai.lastTab") private var selectedTab = 0
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @StateObject private var familyManager = FamilyManager.shared
    @ObservedObject private var authService = AuthenticationService.shared
    @AppStorage(MemoirPersistenceUserDefaults.suggestAccountLinkAfterBook) private var suggestBookBackup = false
    @State private var bookBackupBannerDismissed = false
    @State private var activeStorybookBannerJob: FirestoreSyncService.ActiveStorybookCloudJob?
    @State private var storybookJobsListener: ListenerRegistration?

    private var showBookBackupNudge: Bool {
        suggestBookBackup && authService.isAnonymous && !bookBackupBannerDismissed
    }

    var body: some View {
        ZStack {
            // Soft background base
            Color(red: 0.98, green: 0.94, blue: 0.86)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                activeStorybookJobBanner
                TabView(selection: $selectedTab) {
                    HomepageView()
                        .environmentObject(profileVM)
                        .tabItem {
                            Image(systemName: "house.fill")
                            Text("Home")
                        }
                        .tag(0)
                        .onAppear {
                            UITabBar.appearance().isHidden = false
                        }

                    RecentMemoriesView(selectedTab: $selectedTab)
                        .environmentObject(profileVM)
                        .tabItem {
                            Image(systemName: "clock.fill")
                            Text("Saved Stories")
                        }
                        .tag(1)
                        .onAppear {
                            UITabBar.appearance().isHidden = false
                        }

                    // MARK: - Family Tab (Commented out for development)
                    // TODO: Uncomment when family features are ready for production
                    /*
                    FamilyView()
                        .environmentObject(profileVM)
                        .environmentObject(familyManager)
                        .tabItem {
                            Image(systemName: "person.3.fill")
                            Text("Family")
                        }
                        .tag(2)
                        .onAppear {
                            UITabBar.appearance().isHidden = false
                        }
                    */
                }
                .ignoresSafeArea(edges: .bottom)
                .accentColor(.black)
                .background(.ultraThinMaterial)
                .onAppear {
                    let cream = UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 0.6)
                    UITabBar.appearance().backgroundColor = cream
                    UITabBar.appearance().barTintColor = cream
                    tutorialCoordinator.runMigrationIfNeeded(profileID: profileVM.selectedProfile.id)
                    tutorialCoordinator.refreshAvailability(profileID: profileVM.selectedProfile.id)
                    attachStorybookJobsListener()
                }
                .onDisappear {
                    storybookJobsListener?.remove()
                    storybookJobsListener = nil
                }
                .onChange(of: profileVM.selectedProfile.id) { _, newID in
                    tutorialCoordinator.registerActiveProfile(newID)
                    tutorialCoordinator.refreshAvailability(profileID: newID)
                    tutorialCoordinator.reloadBonusState(profileID: newID)
                    attachStorybookJobsListener()
                }
                .onReceive(NotificationCenter.default.publisher(for: .tutorialSelectHomeTab)) { _ in
                    selectedTab = 0
                }
            }

            if showBookBackupNudge {
                bookBackupBanner
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // (Onboarding overlay removed – handled globally)
    }

    private var bookBackupBanner: some View {
        let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(terracotta)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Back up your books")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Sign in with Apple or Google so your generated books and sync survive reinstalling the app.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    bookBackupBannerDismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            SignInWithAppleButton(.signIn) { request in
                let hashed = AuthenticationService.shared.prepareAppleSignIn()
                request.nonce = hashed
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                    Task {
                        do {
                            try await AuthenticationService.shared.linkAppleAccount(credential: credential)
                        } catch {
                            print("❌ Link Apple failed: \(error.localizedDescription)")
                        }
                    }
                case .failure(let error):
                    print("❌ Apple sign-in failed: \(error.localizedDescription)")
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                Task {
                    do {
                        try await AuthenticationService.shared.linkGoogleAccount()
                    } catch {
                        print("❌ Link Google failed: \(error.localizedDescription)")
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                        Text("G")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    Text("Link Google account")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white.opacity(0.95))
                .foregroundColor(Color.black.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private var activeStorybookJobBanner: some View {
        if let job = activeStorybookBannerJob, path.isEmpty {
            Button {
                NotificationCenter.default.post(name: .navigateToCloudStorybookGeneration, object: nil)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bannerTitle(for: job))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    if job.progressTotal > 0, job.status == "running" {
                        ProgressView(value: Double(job.progressCompleted), total: Double(job.progressTotal))
                            .tint(Color(red: 0.82, green: 0.45, blue: 0.32))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.14))
            }
            .buttonStyle(.plain)
        }
    }

    private func bannerTitle(for job: FirestoreSyncService.ActiveStorybookCloudJob) -> String {
        switch job.status {
        case "queued", "ranking":
            return "Preparing your storybook…"
        case "running":
            let m = max(job.progressTotal, 1)
            return "Generating your storybook — \(job.progressCompleted) of \(m) memories"
        case "aiComplete":
            return "Almost done — tap to finish your book"
        case "failed":
            return "Generation hit a snag — tap to retry"
        default:
            return "Storybook in progress — tap to open"
        }
    }

    private func attachStorybookJobsListener() {
        storybookJobsListener?.remove()
        guard let uid = Auth.auth().currentUser?.uid else {
            activeStorybookBannerJob = nil
            return
        }
        let pid = profileVM.selectedProfile.id.uuidString.lowercased()
        let q = Firestore.firestore()
            .collection("users").document(uid)
            .collection("storybookJobs")
            .order(by: "createdAt", descending: true)
            .limit(to: 25)
        storybookJobsListener = q.addSnapshotListener { snap, _ in
            guard let docs = snap?.documents else { return }
            let active = Set(["queued", "ranking", "running", "aiComplete"])
            var found: FirestoreSyncService.ActiveStorybookCloudJob?
            for d in docs {
                let data = d.data()
                let p = String(describing: data["profileId"] ?? "").lowercased()
                guard p == pid else { continue }
                let st = String(describing: data["status"] ?? "")
                guard active.contains(st) else { continue }
                let prog = data["progress"] as? [String: Any] ?? [:]
                let completed = (prog["completedMemoryCount"] as? NSNumber)?.intValue ?? (prog["completedMemoryCount"] as? Int) ?? 0
                let total = (prog["totalMemories"] as? NSNumber)?.intValue ?? (prog["totalMemories"] as? Int) ?? 0
                let cur = String(describing: prog["currentStatus"] ?? "")
                found = FirestoreSyncService.ActiveStorybookCloudJob(
                    jobId: d.documentID,
                    status: st,
                    progressCompleted: completed,
                    progressTotal: total,
                    currentStatus: cur
                )
                break
            }
            DispatchQueue.main.async {
                self.activeStorybookBannerJob = found
            }
        }
    }
}

#Preview {
    MainTabView(path: .constant(NavigationPath()))
        .environmentObject(ProfileViewModel())
        .environmentObject(TutorialCoordinator.shared)
}
