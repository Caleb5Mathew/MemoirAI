import Foundation

struct ProfileContentScope: Equatable {
    let userID: String
    let profileID: UUID
    let requestID: UUID

    init(userID: String, profileID: UUID, requestID: UUID = UUID()) {
        self.userID = userID
        self.profileID = profileID
        self.requestID = requestID
    }

    func isCurrent(userID: String?, profileID: UUID, requestID: UUID?) -> Bool {
        self.userID == userID && self.profileID == profileID && self.requestID == requestID
    }
}
