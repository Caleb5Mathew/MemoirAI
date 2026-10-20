import CryptoKit
import Foundation
import Combine

struct OnboardingMemoryPreflightKey: Equatable {
    let userID: String
    let profileID: UUID
    let name: String
    let audience: OnboardingAudience?
    let storyteller: OnboardingStoryteller?
    let prompt: String
    let story: String
    let rawTranscript: String?
    let audioURL: URL?
    let audioDigest: String?

    static func digest(of url: URL?) throws -> String? {
        guard let url else { return nil }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty else { throw MemoryCreationError.emptyAudio }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Shares completed-audio preparation between the photo step and final submission.
@MainActor
final class OnboardingMemoryPreflight: ObservableObject {
    private(set) var key: OnboardingMemoryPreflightKey?
    private var task: Task<String, Error>?
    private var revision = UUID()

    func start(key: OnboardingMemoryPreflightKey, operation: @escaping @MainActor () async throws -> String) {
        if self.key == key, task != nil { return }
        invalidate()
        self.key = key
        task = Task { try await operation() }
    }

    func value(for expectedKey: OnboardingMemoryPreflightKey) async throws -> String {
        guard key == expectedKey, let task else { throw CancellationError() }
        let expectedRevision = revision
        do {
            let result = try await task.value
            guard revision == expectedRevision, key == expectedKey else { throw CancellationError() }
            return result
        } catch {
            if revision == expectedRevision { invalidate() }
            throw error
        }
    }

    func invalidate() {
        task?.cancel()
        task = nil
        key = nil
        revision = UUID()
    }
}
