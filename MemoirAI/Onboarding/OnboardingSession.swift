import Foundation

enum OnboardingAudience: String, Codable, CaseIterable {
    case myself
    case someoneElse
    case myChildren
    case parentOrGrandparent
    case notSure

    var subtitle: String {
        switch self {
        case .myself: return "A book about your life"
        case .someoneElse: return "A book about someone you care about"
        case .myChildren: return "A keepsake they can grow up with"
        case .parentOrGrandparent: return "Help preserve their stories"
        case .notSure: return "See how Memoir works"
        }
    }

    var title: String {
        switch self {
        case .myself: return "My life story"
        case .someoneElse: return "Someone else"
        case .myChildren: return "Stories for my children"
        case .parentOrGrandparent: return "A parent or grandparent"
        case .notSure: return "I’m just exploring"
        }
    }
}

enum OnboardingStoryteller: String, Codable, CaseIterable {
    case subject, helper
}

struct OnboardingSession: Codable, Equatable {
    var stage = 0
    var audience: OnboardingAudience?
    var narratorName = ""
    var storyteller: OnboardingStoryteller?
    var profileID = UUID()
    var memoryID = UUID()
    var requestID = UUID().uuidString

    mutating func resetGeneratedIdentifiers() {
        profileID = UUID()
        memoryID = UUID()
        requestID = UUID().uuidString
    }
}

struct OnboardingSessionStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: String) -> OnboardingSession {
        guard let data = defaults.data(forKey: key(userID)),
              let session = try? decoder.decode(OnboardingSession.self, from: data) else {
            return OnboardingSession()
        }
        return session
    }

    func save(_ session: OnboardingSession, userID: String) {
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: key(userID))
    }

    func clear(userID: String) {
        defaults.removeObject(forKey: key(userID))
    }

    private func key(_ userID: String) -> String {
        "memoir_onboarding_v5_\(userID)"
    }
}
