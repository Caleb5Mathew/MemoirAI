import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @StateObject private var familyManager = FamilyManager.shared

    var body: some View {
        ZStack {
            // Soft background base
            Color(red: 0.98, green: 0.94, blue: 0.86)
                .ignoresSafeArea()

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
            .ignoresSafeArea(edges: .bottom)      // ← collapse the home‐indicator inset
            .accentColor(.black)
            .background(.ultraThinMaterial)        // make TabView translucent
            .onAppear {
                // Optional visual polish for TabBar
                let cream = UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 0.6)
                UITabBar.appearance().backgroundColor = cream
                UITabBar.appearance().barTintColor    = cream
                tutorialCoordinator.runMigrationIfNeeded(profileID: profileVM.selectedProfile.id)
                tutorialCoordinator.refreshAvailability(profileID: profileVM.selectedProfile.id)
            }
            .onChange(of: profileVM.selectedProfile.id) { _, newID in
                tutorialCoordinator.registerActiveProfile(newID)
                tutorialCoordinator.refreshAvailability(profileID: newID)
                tutorialCoordinator.reloadBonusState(profileID: newID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .tutorialSelectHomeTab)) { _ in
                selectedTab = 0
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // (Onboarding overlay removed – handled globally)
    }
}

#Preview {
    MainTabView()
        .environmentObject(ProfileViewModel())
        .environmentObject(TutorialCoordinator.shared)
}
