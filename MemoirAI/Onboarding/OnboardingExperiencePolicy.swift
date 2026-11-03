import Foundation

enum OnboardingInputReadiness: String, Equatable, CaseIterable {
    case empty
    case tooShort = "too_short"
    case tooLong = "too_long"
    case needsStoryteller = "needs_storyteller"
    case recording
    case finalizing
    case ready

    static func evaluate(story: String, isRecording: Bool, isFinalizing: Bool,
                         audience: OnboardingAudience?, storyteller: OnboardingStoryteller?) -> Self {
        if isRecording { return .recording }
        if isFinalizing { return .finalizing }
        if OnboardingRecordingCopy.needsStorytellerChoice(for: audience), storyteller == nil {
            return .needsStoryteller
        }
        if story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if OnboardingMemoryValidation.exceedsMaximumLength(story) { return .tooLong }
        return OnboardingMemoryValidation.normalizedTranscript(story) == nil ? .tooShort : .ready
    }
}

enum OnboardingResumePolicy {
    enum Destination: String, Equatable {
        case audience, name, record, meetAlex
    }

    static func scopedSession(_ saved: OnboardingSession, profileID: UUID) -> OnboardingSession {
        guard saved.profileID != profileID else { return saved }
        var fresh = OnboardingSession()
        fresh.profileID = profileID
        return fresh
    }

    static func destination(for session: OnboardingSession) -> Destination {
        guard let audience = session.audience else { return .audience }
        let nameLength = session.narratorName.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard (1...100).contains(nameLength) else {
            return audience == .notSure ? .meetAlex : .name
        }
        // A stored generation or reveal stage never starts work without an explicit action.
        return .record
    }
}
