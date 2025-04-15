//
//  MainTabView.swift
//  MemoirAI
//
//  Created by user941803 on 4/6/25.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomepageView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)

            RecentMemoriesView()
                .tabItem {
                    Image(systemName: "clock.fill")
                    Text("Recent")
                }
                .tag(1)
        }
        .accentColor(.black)
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
