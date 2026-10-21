import SwiftUI
import AuthenticationServices

struct MainTabView: View {
    @Environment(\.openURL) private var openURL
    @Binding var path: NavigationPath
    @AppStorage("memoirai.lastTab") private var selectedTab = 0
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @ObservedObject private var authService = AuthenticationService.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @AppStorage(MemoirPersistenceUserDefaults.suggestAccountLinkAfterBook) private var suggestBookBackup = false
    @AppStorage("memoirai.notificationPromptDismissed") private var notificationPromptDismissed = false
    @State private var showProfileHub = false
    @State private var showProfileSwitcher = false
    @State private var bookBackupBannerDismissed = false
    @State private var showEmailBackupSheet = false
    @State private var pendingAccessRequestCount = 0
    @State private var showAccessRequests = false
    @State private var accountLinkError: String?

    private var showBookBackupNudge: Bool {
        suggestBookBackup && authService.isAnonymous && !bookBackupBannerDismissed
    }

    var body: some View {
        ZStack {
            // Soft background base
            LinenTheme.paper
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image("MemoirBrandIcon")
                        .resizable().scaledToFit().frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    Text("memoir").font(LinenTheme.heading(27)).tracking(-1.2)
                    Spacer(minLength: 8)
                    Button { showProfileSwitcher = true } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Switch profiles")
                    Button { showProfileHub = true } label: {
                        Image(systemName: "person")
                            .frame(width: 38, height: 38)
                            .background(LinenTheme.surface, in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Your profile")
                }
                .foregroundStyle(LinenTheme.ink)
                .padding(.horizontal, 24)
                .frame(minHeight: 64)
                .adaptiveContentWidth(AdaptiveLayoutPolicy.readableMaxWidth)
                .background(LinenTheme.paper)
                .overlay(alignment: .bottom) { Rectangle().fill(LinenTheme.line).frame(height: 1) }
                TabView(selection: $selectedTab) {
                    HomepageView {
                        guard path.isEmpty else { return }
                        StorybookSeenTracker.shared.noteUserNavigationIntent()
                        path.append(StorybookRootRoute.openBook)
                    }
                        .environmentObject(profileVM)
                        .tabItem {
                            Image(systemName: "house.fill")
                            Text("Home")
                        }
                        .tag(0)
                        .toolbar(.hidden, for: .tabBar)

                    RecentMemoriesView(selectedTab: $selectedTab)
                        .environmentObject(profileVM)
                        .tabItem {
                            Image(systemName: "bookmark")
                            Text("Saved Stories")
                        }
                        .tag(1)
                        .toolbar(.hidden, for: .tabBar)
                }
                .toolbar(.hidden, for: .tabBar)
                .tint(LinenTheme.accent)
                .background(LinenTheme.paper)
                .onAppear {
                    tutorialCoordinator.runMigrationIfNeeded(profileID: profileVM.selectedProfile.id)
                    tutorialCoordinator.refreshAvailability(profileID: profileVM.selectedProfile.id)
                }
                .onChange(of: selectedTab, initial: true) { oldTab, newTab in
                    if oldTab != newTab { Haptics.selection() }
                    ProductAnalytics.shared.track("Tab Viewed", ["tab": newTab == 1 ? "memories" : "home"])
                }
                .onChange(of: profileVM.selectedProfile.id) { _, newID in
                    tutorialCoordinator.registerActiveProfile(newID)
                    tutorialCoordinator.refreshAvailability(profileID: newID)
                    tutorialCoordinator.reloadBonusState(profileID: newID)
                }
                .onReceive(NotificationCenter.default.publisher(for: .tutorialSelectHomeTab)) { _ in
                    selectedTab = 0
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        if !notificationPromptDismissed,
                           NotificationPermissionPolicy.action(for: notificationManager.authorizationStatus) != .none {
                            notificationPermissionBanner
                        }
                        if showBookBackupNudge {
                            bookBackupBanner
                        }
                        if pendingAccessRequestCount > 0 {
                            accessRequestsBanner
                        }
                    }
                    .adaptiveContentWidth(AdaptiveLayoutPolicy.bannerMaxWidth)
                    .padding(.horizontal, 16)
                    .padding(.top, showBookBackupNudge || pendingAccessRequestCount > 0 ||
                             (!notificationPromptDismissed && NotificationPermissionPolicy.action(for: notificationManager.authorizationStatus) != .none) ? 8 : 0)
                }
                .sheet(isPresented: $showAccessRequests, onDismiss: {
                    Task { await refreshPendingAccessRequestCount() }
                }) {
                    NavigationStack {
                        PendingRequestsView()
                    }
                }
                .task {
                    notificationManager.refreshAuthorizationStatus()
                    await refreshPendingAccessRequestCount()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    notificationManager.refreshAuthorizationStatus()
                    Task { await refreshPendingAccessRequestCount() }
                }
                bottomNavigation
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showProfileHub) { LinenProfileHub().environmentObject(profileVM) }
        .sheet(isPresented: $showProfileSwitcher) { ProfileSwitcherView().environmentObject(profileVM) }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            "Account Could Not Be Linked",
            isPresented: Binding(
                get: { accountLinkError != nil },
                set: { if !$0 { accountLinkError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { accountLinkError = nil }
        } message: {
            Text(accountLinkError ?? "Please try again.")
        }
        // (Onboarding overlay removed – handled globally)
    }

    private var bottomNavigation: some View {
        HStack(spacing: 20) {
            ForEach(0..<2) { tab in
                Button { selectedTab = tab } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab == 0 ? "house" : "bookmark")
                            .font(.system(size: 18, weight: .regular))
                        Text(tab == 0 ? "Home" : "Saved Stories")
                            .font(LinenTheme.body(12, weight: selectedTab == tab ? .bold : .regular))
                    }
                    .foregroundStyle(selectedTab == tab ? LinenTheme.accent : LinenTheme.secondary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 45)
                    .background(selectedTab == tab ? LinenTheme.surface : Color.clear, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .accessibilityIdentifier(tab == 0 ? "linenHomeTab" : "linenSavedStoriesTab")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .adaptiveContentWidth(AdaptiveLayoutPolicy.readableMaxWidth)
        .frame(maxWidth: .infinity)
        .background(LinenTheme.paper)
        .overlay(alignment: .top) { Rectangle().fill(LinenTheme.line).frame(height: 1) }
    }

    private var notificationPermissionBanner: some View {
        let action = NotificationPermissionPolicy.action(for: notificationManager.authorizationStatus)
        let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(terracotta)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Don’t miss family requests")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Get notified when someone asks to hear a memory you shared.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    notificationPromptDismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification reminder")
            }

            Button(action == .openSettings ? "Open Notification Settings" : "Enable Notifications") {
                switch action {
                case .request:
                    notificationManager.requestPermission()
                case .openSettings:
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                case .none:
                    break
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(terracotta)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    private var accessRequestsBanner: some View {
        let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
        return Button {
            showAccessRequests = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(terracotta)
                Text(pendingAccessRequestCount == 1
                     ? "Someone asked to hear your memories"
                     : "\(pendingAccessRequestCount) people asked to hear your memories")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func refreshPendingAccessRequestCount() async {
        guard authService.isSignedIn else {
            pendingAccessRequestCount = 0
            return
        }
        let requests = (try? await SharedAccessService.shared.fetchPendingRequests()) ?? []
        pendingAccessRequestCount = requests.count
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
                            accountLinkError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    accountLinkError = error.localizedDescription
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
                        accountLinkError = error.localizedDescription
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
