import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var profileVM = ProfileViewModel()

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

                RecentMemoriesView()
                    .environmentObject(profileVM)
                    .tabItem {
                        Image(systemName: "clock.fill")
                        Text("Recent")
                    }
                    .tag(1)
                    .onAppear {
                        UITabBar.appearance().isHidden = true
                    }
            }
            .ignoresSafeArea(edges: .bottom)      // ← collapse the home‐indicator inset
            .accentColor(.black)
            .background(.ultraThinMaterial)        // make TabView translucent
            .onAppear {
                // Optional visual polish for TabBar
                let cream = UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 0.6)
                UITabBar.appearance().backgroundColor = cream
                UITabBar.appearance().barTintColor    = cream
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
    }
}

#Preview {
    MainTabView()
}
