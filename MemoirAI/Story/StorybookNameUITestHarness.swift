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
