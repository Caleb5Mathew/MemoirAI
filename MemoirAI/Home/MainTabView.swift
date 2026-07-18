import SwiftUI
import AuthenticationServices

struct MainTabView: View {
    @Binding var path: NavigationPath
    @AppStorage("memoirai.lastTab") private var selectedTab = 0
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @StateObject private var familyManager = FamilyManager.shared
    @ObservedObject private var authService = AuthenticationService.shared
    @AppStorage(MemoirPersistenceUserDefaults.suggestAccountLinkAfterBook) private var suggestBookBackup = false
    @State private var bookBackupBannerDismissed = false
    @State private var showEmailBackupSheet = false

    private var showBookBackupNudge: Bool {
        suggestBookBackup && authService.isAnonymous && !bookBackupBannerDismissed
    }

    var body: some View {
        ZStack {
            // Soft background base
            Color(red: 0.98, green: 0.94, blue: 0.86)
                .ignoresSafeArea()

            VStack(spacing: 0) {
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
                }
                .onChange(of: selectedTab) { _, _ in
                    Haptics.selection()
                }
                .onChange(of: profileVM.selectedProfile.id) { _, newID in
                    tutorialCoordinator.registerActiveProfile(newID)
                    tutorialCoordinator.refreshAvailability(profileID: newID)
                    tutorialCoordinator.reloadBonusState(profileID: newID)
                }
                .onReceive(NotificationCenter.default.publisher(for: .tutorialSelectHomeTab)) { _ in
                    selectedTab = 0
                }
                .overlay(alignment: .top) {
                    if showBookBackupNudge {
                        bookBackupBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }
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

            Button {
                showEmailBackupSheet = true
            } label: {
                Text("Use email instead")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(terracotta)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        .sheet(isPresented: $showEmailBackupSheet) {
            EmailAuthSheet { _ in
                bookBackupBannerDismissed = true
            }
        }
    }
}

#Preview {
    MainTabView(path: .constant(NavigationPath()))
        .environmentObject(ProfileViewModel())
        .environmentObject(TutorialCoordinator.shared)
}
