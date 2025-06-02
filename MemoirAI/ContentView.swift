import SwiftUI

struct ContentView: View {
    // 1️⃣ the shared router that MemoirAIApp’s `.onOpenURL` will call
    @StateObject private var nav = NavigationRouter.shared
    
    // 2️⃣ one NavigationPath to drive programmatic pushes
    @State private var path = NavigationPath()
    
    // 3️⃣ Core-Data context you were already injecting
    private var moc = PersistenceController.shared.container.viewContext
    
    var body: some View {
        NavigationStack(path: $path) {
            // your existing tab bar
            MainTabView()
                .environment(\.managedObjectContext, moc)
                // 4️⃣ whenever the router publishes a new UUID, push it
                .onReceive(nav.$selectedMemoryID.compactMap { $0 }) { id in
                    path.append(id)
                }
                // 5️⃣ if you pop back with the system swipe, clear the router
                .onChange(of: path) { newValue in
                    if newValue.isEmpty { nav.clear() }
                }
                // 6️⃣ declare how to build the destination view
                .navigationDestination(for: UUID.self) { id in
                    if let entry = PersistenceController.shared.entry(id: id) {
                        MemoryDetailView(memory: entry)
                            .onDisappear { nav.clear() }
                    } else {
                        // fallback if the UUID isn’t in Core Data
                        Text("Memory not found").font(.headline)
                    }
                }
        }
        // share the router so child views could react too
        .environmentObject(nav)
    }
}

#if DEBUG
#Preview { ContentView() }
#endif
