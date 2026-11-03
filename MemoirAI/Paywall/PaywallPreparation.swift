import Foundation

enum SubscriptionPaywallOutcome: Equatable {
    case presented
    case entitlementActive
    case dismissedWithoutOffer
}

enum PaywallPreparationError: Error {
    case timeout
    case accountChanged
    case unavailable(stage: String)
}

/// A deadline stops waiting for an SDK callback without letting its late result update the screen.
@MainActor
final class PaywallPreparation {
    private var requestID: UUID?
    private var operationTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var completion: ((Result<Void, Error>) -> Void)?

    @discardableResult
    func start(
        timeoutNanoseconds: UInt64 = 20_000_000_000,
        operation: @escaping @MainActor () async throws -> Void,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) -> Bool {
        guard requestID == nil else { return false }
        let id = UUID()
        requestID = id
        self.completion = completion
        operationTask = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                try await operation()
                try Task.checkCancellation()
                self?.finish(id: id, result: .success(()))
            } catch {
                self?.finish(id: id, result: .failure(error))
            }
        }
        deadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
            catch { return }
            self?.finish(id: id, result: .failure(PaywallPreparationError.timeout))
        }
        return true
    }

    func cancel() {
        guard let id = requestID else { return }
        finish(id: id, result: .failure(CancellationError()))
    }

    private func finish(id: UUID, result: Result<Void, Error>) {
        guard requestID == id else { return }
        requestID = nil
        operationTask?.cancel()
        deadlineTask?.cancel()
        operationTask = nil
        deadlineTask = nil
        let callback = completion
        completion = nil
        callback?(result)
    }
}
