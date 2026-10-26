import Foundation

enum OnboardingAudience: String, Codable, CaseIterable {
    case myself
    case someoneElse
    case myChildren
    case parentOrGrandparent
    case notSure

    var title: String {
        switch self {
        case .myself: return "My life story"
        case .someoneElse: return "Someone I care about"
        case .myChildren: return "Stories for my children"
        case .parentOrGrandparent: return "My parent or grandparent"
        case .notSure: return "I’m just exploring"
        }
    }
}

enum OnboardingStoryteller: String, Codable, CaseIterable {
    case subject, helper
}

enum OnboardingRecordingCopy {
    static func needsStorytellerChoice(for audience: OnboardingAudience?) -> Bool {
        audience == .someoneElse || audience == .parentOrGrandparent
    }

    static func prompt(for audience: OnboardingAudience?, name: String) -> String {
        guard needsStorytellerChoice(for: audience) else {
            return "What’s one of your favorite childhood memories?"
        }
        return "Share one of \(normalizedName(name))’s favorite childhood memories."
    }

    static func guidance(for audience: OnboardingAudience?, name: String) -> String {
        guard needsStorytellerChoice(for: audience) else {
            return "Tap the microphone below and answer the question to get started."
        }
        let subjectName = normalizedName(name)
        return "You can tell it for \(subjectName), or have \(subjectName) tell it in their own words."
    }

    static func subjectChoiceTitle(name: String) -> String {
        "Let \(normalizedName(name)) tell it"
    }

    private static func normalizedName(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "them" : value
    }
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
