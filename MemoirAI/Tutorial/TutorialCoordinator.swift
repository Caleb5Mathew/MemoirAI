//
//  TutorialCoordinator.swift
//  MemoirAI
//

import Foundation
import SwiftUI
import Combine
import CoreData

extension Notification.Name {
    /// Posted to switch MainTabView to Home (tab 0) after recording a memory in the tutorial.
    static let tutorialSelectHomeTab = Notification.Name("tutorialSelectHomeTab")
    /// Posted to dismiss all pushed/presented views and return to root Home during tutorial.
    static let tutorialDismissToHome = Notification.Name("tutorialDismissToHome")
}

/// Guided first-run tutorial: coach marks + optional one-time bonus storybook image when free preview is exhausted.
@MainActor
final class TutorialCoordinator: ObservableObject {
    static let shared = TutorialCoordinator()

    /// Current step in the flow (`none` when not running).
    @Published private(set) var currentStep: TutorialStep = .none

    /// True while the user has not finished or skipped the guided flow.
    @Published private(set) var isTutorialActive: Bool = false

    /// Bumped to reset `NavigationStack` on Home so the user returns to the root before “Your Book”.
    @Published private(set) var homeNavigationResetToken: Int = 0

    /// Set when a memory is saved while the tutorial expects it (unlocks bonus eligibility).
    @Published private(set) var memorySavedDuringTutorialFlow: Bool = false

    /// One-time bonus: generate one image even when `FreePreviewConfig` free pages are exhausted.
    @Published private(set) var tutorialBonusConsumed: Bool = false

    /// Screen currently visible to the user. Overlay only renders when it matches the active step.
    @Published private(set) var visibleScreen: TutorialScreen = .unknown

    /// Anchors reported directly by views (bypasses PreferenceKey which can fail across nested NavigationStacks).
    @Published var directAnchors: [TutorialStep: CGRect] = [:]

    private let migrationKey = "guidedTutorial_migration_v1_done"
    private let cloudPrefix = "memoir_guidedTutorial_"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadFromStorage()
        NotificationCenter.default.publisher(for: .memorySaved)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleMemorySaved()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadFromStorage()
            }
            .store(in: &cancellables)
    }

    // MARK: - Scope

    private func scopeKey(profileID: UUID) -> String {
        let uid = MemoryUserScope.currentFirebaseUserId ?? "anonymous"
        return "\(uid)_\(profileID.uuidString)"
    }

    private func baseKey(for profileID: UUID, suffix: String) -> String {
        "\(cloudPrefix)\(suffix)_\(scopeKey(profileID: profileID))"
    }

    // MARK: - Migration

    /// Call once from main UI after Core Data is ready. Existing users with memories skip the tutorial.
    func runMigrationIfNeeded(profileID: UUID) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)

        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.fetchLimit = 1
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileID)

        if (try? context.count(for: request)) ?? 0 > 0 {
            markCompletedQuietly(profileID: profileID)
        }
    }

    // MARK: - Lifecycle

    /// Start or resume tutorial when appropriate (onboarding done, not completed/skipped for this profile).
    /// NOTE: Coach-mark tutorial disabled — using onboarding intro screens instead.
    func refreshAvailability(profileID: UUID) {
        isTutorialActive = false
        currentStep = .none
        return

        // ── disabled coach-mark tutorial ──
        /*
        registerActiveProfile(profileID)
        syncCloud()

        if isCompleted(profileID: profileID) || isSkipped(profileID: profileID) {
            isTutorialActive = false
            currentStep = .none
            return
        }

        let step = loadStep(profileID: profileID)
        if step == .finished {
            isTutorialActive = false
            currentStep = .none
            return
        }

        if step == .none {
            currentStep = .homeIntro
            saveStep(profileID: profileID)
        } else {
            currentStep = step
        }

        isTutorialActive = true
        memorySavedDuringTutorialFlow = loadMemorySavedFlag(profileID: profileID)
        tutorialBonusConsumed = loadBonusConsumed(profileID: profileID)
        */
    }

    func goToStep(_ step: TutorialStep, profileID: UUID) {
        currentStep = step
        saveStep(profileID: profileID)
        if step == .finished {
            isTutorialActive = false
        }
    }

    func nextFromHomeIntro(profileID: UUID) {
        goToStep(.homeContinueMemoir, profileID: profileID)
    }

    func onMemoirViewAppeared(profileID: UUID) {
        guard isTutorialActive, currentStep == .homeContinueMemoir else { return }
        goToStep(.memoirPickChapter, profileID: profileID)
    }

    func onChapterJourneyAppeared(profileID: UUID) {
        guard isTutorialActive, currentStep == .memoirPickChapter else { return }
        goToStep(.chapterPickPrompt, profileID: profileID)
    }

    func onRecordingViewAppeared(profileID: UUID) {
        guard isTutorialActive, currentStep == .chapterPickPrompt else { return }
        goToStep(.recordingSaveMemory, profileID: profileID)
    }

    func onRecordMemoryViewAppeared(profileID: UUID) {
        guard isTutorialActive else { return }
        // Quick “Start Recording” from Home while tutorial is early: still coach the save step.
        switch currentStep {
        case .homeIntro, .homeContinueMemoir, .memoirPickChapter, .chapterPickPrompt:
            goToStep(.recordingSaveMemory, profileID: profileID)
        default:
            break
        }
    }

    func onStoryPageAppeared(profileID: UUID) {
        guard isTutorialActive else { return }
        if currentStep == .homeYourBook {
            goToStep(.storybookCreate, profileID: profileID)
        }
    }

    func skipTutorial(profileID: UUID) {
        setSkipped(true, profileID: profileID)
        if !memorySavedDuringTutorialFlow && !loadMemorySavedFlag(profileID: profileID) {
            setTutorialBonusEligible(false, profileID: profileID)
        }
        currentStep = .finished
        saveStep(profileID: profileID)
        isTutorialActive = false
    }

    func completeTutorial(profileID: UUID) {
        markCompleted(profileID: profileID)
        currentStep = .finished
        saveStep(profileID: profileID)
        isTutorialActive = false
    }

    /// Call from StoryPage after successful generation while in tutorial, or when user taps “Done” on last coach mark.
    func finishStorybookTutorialStep(profileID: UUID) {
        completeTutorial(profileID: profileID)
    }

    // MARK: - Memory / bonus

    private func handleMemorySaved() {
        guard isTutorialActive, currentStep == .recordingSaveMemory else { return }
        // profileID from selected profile — we need to pass it; storage uses last known profile from UserDefaults
        guard let pid = UserDefaults.standard.string(forKey: "guidedTutorial_lastProfileUUID"),
              let uuid = UUID(uuidString: pid) else { return }

        memorySavedDuringTutorialFlow = true
        setMemorySavedFlag(true, profileID: uuid)
        setTutorialBonusEligible(true, profileID: uuid)

        goToStep(.homeYourBook, profileID: uuid)
        homeNavigationResetToken += 1
        NotificationCenter.default.post(name: .tutorialDismissToHome, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .tutorialSelectHomeTab, object: nil)
        }
    }

    func registerActiveProfile(_ profileID: UUID) {
        UserDefaults.standard.set(profileID.uuidString, forKey: "guidedTutorial_lastProfileUUID")
    }

    func setVisibleScreen(_ screen: TutorialScreen) {
        visibleScreen = screen
    }

    func shouldRenderOverlay() -> Bool {
        guard isTutorialActive else { return false }
        guard currentStep != .none && currentStep != .finished else { return false }

        let expected = expectedScreen(for: currentStep)
        guard screenMatches(expected: expected, actual: visibleScreen, step: currentStep) else { return false }

        return true
    }

    /// Merged anchors: direct reports take priority over PreferenceKey values.
    func mergedAnchors(with preferenceAnchors: [TutorialStep: CGRect]) -> [TutorialStep: CGRect] {
        preferenceAnchors.merging(directAnchors) { _, direct in direct }
    }

    func reportAnchor(_ step: TutorialStep, rect: CGRect) {
        if directAnchors[step] != rect {
            directAnchors[step] = rect
        }
    }

    func clearAnchor(_ step: TutorialStep) {
        directAnchors.removeValue(forKey: step)
    }

    /// True when the user may generate one image despite free preview exhaustion (tutorial bonus).
    func canUseTutorialBonusGeneration(isSubscribed: Bool, profileID: UUID) -> Bool {
        guard !isSubscribed else { return false }
        loadFromStorage(profileID: profileID)
        guard !loadBonusConsumed(profileID: profileID) else { return false }
        guard loadTutorialBonusEligible(profileID: profileID) else { return false }
        guard loadMemorySavedFlag(profileID: profileID) else { return false }
        guard !FreePreviewConfig.canGenerateFreePreview else { return false }
        return true
    }

    func consumeTutorialBonus(profileID: UUID) {
        tutorialBonusConsumed = true
        setBonusConsumed(true, profileID: profileID)
    }

    func reloadBonusState(profileID: UUID) {
        tutorialBonusConsumed = loadBonusConsumed(profileID: profileID)
        memorySavedDuringTutorialFlow = loadMemorySavedFlag(profileID: profileID)
    }

    // MARK: - Storage

    private func loadFromStorage() {
        guard let pid = UserDefaults.standard.string(forKey: "guidedTutorial_lastProfileUUID"),
              let uuid = UUID(uuidString: pid) else { return }
        loadFromStorage(profileID: uuid)
    }

    private func loadFromStorage(profileID: UUID) {
        syncCloud()
        currentStep = loadStep(profileID: profileID)
        memorySavedDuringTutorialFlow = loadMemorySavedFlag(profileID: profileID)
        tutorialBonusConsumed = loadBonusConsumed(profileID: profileID)
    }

    private func syncCloud() {
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func loadStep(profileID: UUID) -> TutorialStep {
        let key = baseKey(for: profileID, suffix: "step")
        let raw = UserDefaults.standard.string(forKey: key)
            ?? NSUbiquitousKeyValueStore.default.string(forKey: key)
            ?? TutorialStep.none.rawValue
        return TutorialStep(rawValue: raw) ?? .none
    }

    private func saveStep(profileID: UUID) {
        let key = baseKey(for: profileID, suffix: "step")
        UserDefaults.standard.set(currentStep.rawValue, forKey: key)
        NSUbiquitousKeyValueStore.default.set(currentStep.rawValue, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func isCompleted(profileID: UUID) -> Bool {
        let key = baseKey(for: profileID, suffix: "completed")
        return UserDefaults.standard.bool(forKey: key) || NSUbiquitousKeyValueStore.default.bool(forKey: key)
    }

    private func isSkipped(profileID: UUID) -> Bool {
        let key = baseKey(for: profileID, suffix: "skipped")
        return UserDefaults.standard.bool(forKey: key) || NSUbiquitousKeyValueStore.default.bool(forKey: key)
    }

    private func markCompleted(profileID: UUID) {
        let key = baseKey(for: profileID, suffix: "completed")
        UserDefaults.standard.set(true, forKey: key)
        NSUbiquitousKeyValueStore.default.set(true, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func markCompletedQuietly(profileID: UUID) {
        markCompleted(profileID: profileID)
        let key = baseKey(for: profileID, suffix: "step")
        UserDefaults.standard.set(TutorialStep.finished.rawValue, forKey: key)
        NSUbiquitousKeyValueStore.default.set(TutorialStep.finished.rawValue, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func setSkipped(_ value: Bool, profileID: UUID) {
        let key = baseKey(for: profileID, suffix: "skipped")
        UserDefaults.standard.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func loadMemorySavedFlag(profileID: UUID) -> Bool {
        let key = baseKey(for: profileID, suffix: "memorySaved")
        return UserDefaults.standard.bool(forKey: key) || NSUbiquitousKeyValueStore.default.bool(forKey: key)
    }

    private func setMemorySavedFlag(_ value: Bool, profileID: UUID) {
        let key = baseKey(for: profileID, suffix: "memorySaved")
        UserDefaults.standard.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func loadTutorialBonusEligible(profileID: UUID) -> Bool {
        let key = baseKey(for: profileID, suffix: "bonusEligible")
        return UserDefaults.standard.bool(forKey: key) || NSUbiquitousKeyValueStore.default.bool(forKey: key)
    }

    private func setTutorialBonusEligible(_ value: Bool, profileID: UUID) {
        let key = baseKey(for: profileID, suffix: "bonusEligible")
        UserDefaults.standard.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func loadBonusConsumed(profileID: UUID) -> Bool {
        let key = baseKey(for: profileID, suffix: "bonusConsumed")
        return UserDefaults.standard.bool(forKey: key) || NSUbiquitousKeyValueStore.default.bool(forKey: key)
    }

    private func setBonusConsumed(_ value: Bool, profileID: UUID) {
        let key = baseKey(for: profileID, suffix: "bonusConsumed")
        UserDefaults.standard.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func expectedScreen(for step: TutorialStep) -> TutorialScreen {
        switch step {
        case .homeIntro, .homeContinueMemoir, .homeYourBook:
            return .home
        case .memoirPickChapter:
            return .memoir
        case .chapterPickPrompt:
            return .chapterJourney
        case .recordingSaveMemory:
            return .recordMemory
        case .storybookCreate:
            return .storyPage
        case .none, .finished:
            return .unknown
        }
    }

    private func screenMatches(expected: TutorialScreen, actual: TutorialScreen, step: TutorialStep) -> Bool {
        if expected == .unknown { return true }
        if step == .recordingSaveMemory {
            return actual == .recordMemory || actual == .recording
        }
        return expected == actual
    }
}

enum TutorialScreen: String, Codable {
    case unknown
    case home
    case memoir
    case chapterJourney
    case recordMemory
    case recording
    case storyPage
}

enum TutorialStep: String, Codable, CaseIterable {
    case none
    case homeIntro
    case homeContinueMemoir
    case memoirPickChapter
    case chapterPickPrompt
    case recordingSaveMemory
    case homeYourBook
    case storybookCreate
    case finished
}
