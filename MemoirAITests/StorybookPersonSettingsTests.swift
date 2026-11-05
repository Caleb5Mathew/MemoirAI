import Foundation
import Testing
@testable import MemoirAI

struct StorybookPersonSettingsTests {
    @Test func traitsAndExtraDetailsBelongToOnePersonAndAccount() throws {
        let suite = "PersonSettingsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var a = Profile(name: "Audrey")
        a.ethnicity = "Asian"
        a.gender = "Woman"
        a.faceDescription = "Short silver hair"
        let b = Profile(name: "Lauren")
        defaults.set("legacy trait", forKey: "memoirGender")
        defaults.set("legacy details", forKey: "memoirOtherPersonalDetails")
        defaults.set("Wears round glasses", forKey: StorybookPersonSettings.detailsKey(userID: "owner-a", profileID: a.id))
        let first = StorybookPersonSettings(profile: a, userID: "owner-a", defaults: defaults)
        let second = StorybookPersonSettings(profile: b, userID: "owner-a", defaults: defaults)
        let otherAccount = StorybookPersonSettings(profile: a, userID: "owner-b", defaults: defaults)
        #expect(first.ethnicity == "Asian")
        #expect(first.gender == "Woman")
        #expect(first.faceDescription == "Short silver hair")
        #expect(first.otherDetails == "Wears round glasses")
        #expect(second.gender.isEmpty && second.ethnicity.isEmpty && second.faceDescription == nil)
        #expect(second.otherDetails.isEmpty && otherAccount.otherDetails.isEmpty)
    }

    @MainActor @Test func activatingAnotherPersonInvalidatesPendingWorkButRefreshingTraitsDoesNot() {
        let model = StoryPageViewModel()
        let first = Profile(name: "First")
        let second = Profile(name: "Second")
        model.activateProfileSettings(profile: first, userID: "a")
        let initialRun = model.generationRunID
        model.activateProfileSettings(profile: first, userID: "a")
        #expect(model.generationRunID == initialRun)
        model.activateProfileSettings(profile: second, userID: "a")
        #expect(model.generationRunID == initialRun + 1)
        model.activateProfileSettings(profile: second, userID: "b")
        #expect(model.generationRunID == initialRun + 2)
    }

    @MainActor @Test func retryWithoutCapturedFinalizationDoesNotCreateNewGeneration() async {
        let model = StoryPageViewModel()
        let run = model.generationRunID
        await model.retryFinalization()
        #expect(model.generationRunID == run)
        #expect(!model.canRetryFinalization)
        #expect(!model.isLoading)
    }

    @Test func delayedResumeAndPreflightCannotPublishIntoAnotherRunOrAccount() async {
        let profile = UUID()
        let capturedRun: UInt64 = 4
        await Task.yield()
        #expect(!StorybookAsyncRunPolicy.isCurrent(expectedUserID: "a", expectedProfileID: profile, expectedRun: capturedRun,
            currentUserID: "b", currentProfileID: profile, currentRun: capturedRun))
        #expect(!StorybookAsyncRunPolicy.isCurrent(expectedUserID: "a", expectedProfileID: profile, expectedRun: capturedRun,
            currentUserID: "a", currentProfileID: profile, currentRun: capturedRun + 1))
        #expect(!StorybookAsyncRunPolicy.isCurrent(expectedUserID: "a", expectedProfileID: profile, expectedRun: capturedRun,
            currentUserID: "a", currentProfileID: UUID(), currentRun: capturedRun))
    }
}
