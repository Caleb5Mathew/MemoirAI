import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}

#Preview {
    ContentView()
}
