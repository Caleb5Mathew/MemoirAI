import Foundation
import Testing
@testable import MemoirAI

struct StorybookJobProfilePolicyTests {
    @Test func acceptsCanonicalAndLegacyCaseVariants() {
        let profileID = UUID()
        #expect(StorybookJobProfilePolicy.matches(["profileId": profileID.uuidString], profileID: profileID))
        #expect(StorybookJobProfilePolicy.matches(["profileID": profileID.uuidString.lowercased()], profileID: profileID))
    }

    @Test func rejectsMissingMalformedDifferentAndConflictingIdentity() {
        let profileID = UUID()
        #expect(!StorybookJobProfilePolicy.matches([:], profileID: profileID))
        #expect(!StorybookJobProfilePolicy.matches(["profileId": "invalid"], profileID: profileID))
        #expect(!StorybookJobProfilePolicy.matches(["profileId": UUID().uuidString], profileID: profileID))
        #expect(!StorybookJobProfilePolicy.matches(["profileId": profileID.uuidString, "profileID": UUID().uuidString], profileID: profileID))
    }
}
