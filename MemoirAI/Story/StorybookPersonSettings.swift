import Foundation

struct StorybookPersonSettings: Equatable {
    let ethnicity: String
    let gender: String
    let faceDescription: String?
    let otherDetails: String

    static func detailsKey(userID: String, profileID: UUID) -> String {
        "memoirOtherPersonalDetails_" + userID + ":" + profileID.uuidString
    }

    init(profile: Profile, userID: String, defaults: UserDefaults = .standard) {
        ethnicity = profile.ethnicity ?? ""
        gender = profile.gender ?? ""
        faceDescription = profile.faceDescription
        otherDetails = defaults.string(forKey: Self.detailsKey(userID: userID, profileID: profile.id)) ?? ""
    }
}
