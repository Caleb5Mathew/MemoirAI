import SwiftUI
import FBSDKCoreKit

struct ContentView: View {
    @EnvironmentObject var iCloudManager: iCloudManager
    
    // For deep-linking to memory details
    @StateObject private var nav = NavigationRouter.shared
    @State private var path = NavigationPath()
    
    // Local fallback for immediate availability even before iCloud sync
    @AppStorage("hasCompletedOnboarding_local") private var localCompleted: Bool = false
    
    var body: some View {
        let done = localCompleted || iCloudManager.hasCompletedOnboarding
        return Group {
            if done {
                NavigationStack(path: $path) {
                    MainTabView()
                        .onReceive(nav.$selectedMemoryID.compactMap { $0 }) { id in
                            path.append(id)
                        }
                        .onChange(of: path) {
                            if path.isEmpty { nav.clear() }
                        }
                        .navigationDestination(for: UUID.self) { id in
                            if let entry = PersistenceController.shared.entry(id: id) {
                                MemoryDetailView(memory: entry)
                                    .onDisappear { nav.clear() }
                            } else {
                                Text("Memory not found").font(.headline)
                            }
                        }
                }
                .environmentObject(nav)
            } else {
                OnboardingFlow()
            }
        }
        .onAppear {
            // 🎯 CRITICAL: Establish link between ad clicks and app opens
            AppEvents.shared.activateApp()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(iCloudManager.shared)
    }
}
