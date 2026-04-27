//
//  ResumeCoordinator.swift
//  MemoirAI
//
//  Shared navigation token for auto-opening the storybook screen after relaunch.
//

import Foundation
import SwiftUI

/// Pushes the storybook editor from the root `NavigationStack` when the user has an in-flight generation to resume.
enum StorybookRootRoute: Hashable {
    case resumeInProgressGeneration
}

/// How the storybook screen was opened (controls auto-resume of a killed generation).
enum StorybookScreenEntry: Hashable {
    case standard
    case autoResumePendingGeneration
}

private struct StorybookScreenEntryKey: EnvironmentKey {
    static var defaultValue: StorybookScreenEntry = .standard
}

extension EnvironmentValues {
    var storybookScreenEntry: StorybookScreenEntry {
        get { self[StorybookScreenEntryKey.self] }
        set { self[StorybookScreenEntryKey.self] = newValue }
    }
}
