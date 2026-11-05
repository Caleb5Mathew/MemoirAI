#if DEBUG
import SwiftUI

/// The isolated, inactive profile model cannot write test names to cloud profiles.
struct StorybookNameUITestHarness: View {
    @StateObject private var profiles: ProfileViewModel = {
        let model = ProfileViewModel()
        if ProcessInfo.processInfo.arguments.contains("-UITestFieldnotesPreview") {
            model.updateName(for: model.selectedProfile, to: "Margaret")
        }
        return model
    }()

    var body: some View {
        NavigationStack {
            StoryPage()
                .environmentObject(profiles)
                .safeAreaInset(edge: .bottom) {
                    Text(ProcessInfo.processInfo.arguments.contains("-UITestFieldnotesPreview")
                         ? "Sample book · Preview" : profiles.selectedProfile.name)
                        .font(.caption)
                        .accessibilityIdentifier("testSavedMemoirName")
                }
        }
    }
}
#endif

#if DEBUG
/// Runs production navigation against local fixture profiles; selection never writes to cloud.
@MainActor
private final class ProfileNavigationUITestSession: ObservableObject {
    let profiles: ProfileViewModel
    let persistence = PersistenceController(inMemory: true)
    let fixtureError: String?

    init() {
        let model: ProfileViewModel
        var errorMessage: String?
        do {
            guard let defaults = UserDefaults(suiteName: "memoirai.profile-navigation-uitest") else {
                throw CocoaError(.fileReadUnknown)
            }
            if ProcessInfo.processInfo.arguments.contains("-UITestResetProfiles") {
                defaults.removePersistentDomain(forName: "memoirai.profile-navigation-uitest")
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("memoirai-profile-navigation-uitest", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let firstID = UUID(uuidString: "11111111-1111-4111-8111-111111111111"),
                  let secondID = UUID(uuidString: "22222222-2222-4222-8222-222222222222") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let fixtures = [
                Profile(id: firstID, name: "Profile One", createdAt: Date(timeIntervalSince1970: 1)),
                Profile(id: secondID, name: "Profile Two", createdAt: Date(timeIntervalSince1970: 2))
            ]
            let userID = "local-profile-navigation-uitest"
            try JSONEncoder().encode(fixtures).write(to: directory.appendingPathComponent(ProfileStorageScope.fileName(userID: userID)), options: .atomic)
            model = ProfileViewModel(selectionDefaults: defaults, selectionCloudStore: nil, profilesDirectory: directory)
            model.beginUserActivation(userID)
            model.applyHydratedProfiles(fixtures, deletedIDs: [], userID: userID)
        } catch {
            model = ProfileViewModel(selectionCloudStore: nil)
            errorMessage = error.localizedDescription
        }
        profiles = model
        fixtureError = errorMessage
    }

}

struct ProfileNavigationUITestHarness: View {
    @StateObject private var session = ProfileNavigationUITestSession()
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if let fixtureError = session.fixtureError {
                Text("Fixture failed: \(fixtureError)")
            } else {
                NavigationStack(path: $path) {
                    MainTabView(path: $path)
                        .navigationDestination(for: HomeNavigationRoute.self) { route in
                            switch route {
                            case .memoir: MemoirView()
                            case .recordStory: RecordMemoryView()
                            }
                        }
                        .navigationDestination(for: StorybookRootRoute.self) { _ in
                            StoryPage()
                        }
                }
            }
        }
        .environmentObject(session.profiles)
        .environment(\.managedObjectContext, session.persistence.container.viewContext)
    }
}
#endif
