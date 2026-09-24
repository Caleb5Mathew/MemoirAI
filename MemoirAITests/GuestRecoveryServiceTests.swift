import Foundation
import Testing
@testable import MemoirAI

@MainActor
struct GuestRecoveryServiceTests {
    @Test func enrollmentCreatesOneSecretAndUsesExpectedCallableContract() async throws {
        let store = GuestRecoverySecretStoreStub()
        let caller = GuestRecoveryCallerStub()
        let auth = GuestRecoveryAuthenticatorStub(userID: "guest-1", isAnonymous: true)
        let coordinator = GuestRecoveryCoordinator(
            secretStore: store,
            caller: caller,
            authenticator: auth
        )

        try await coordinator.enrollCurrentGuest()
        try await coordinator.enrollCurrentGuest()

        #expect(store.createCount == 2)
        #expect(store.generatedSecretCount == 1)
        #expect(caller.calls.map(\.name) == ["enrollGuestRecovery", "enrollGuestRecovery"])
        #expect(caller.calls.allSatisfy {
            $0.payload["recoverySecret"] as? String == store.secret?.base64EncodedString()
                && $0.payload["protocolVersion"] as? Int == 1
        })
    }

    @Test func recoveryDoesNothingWithoutSavedSecret() async throws {
        let store = GuestRecoverySecretStoreStub()
        let caller = GuestRecoveryCallerStub()
        let auth = GuestRecoveryAuthenticatorStub(userID: "new-guest", isAnonymous: true)
        let coordinator = GuestRecoveryCoordinator(
            secretStore: store,
            caller: caller,
            authenticator: auth
        )

        let result = try await coordinator.recoverCurrentGuestIfAvailable()

        #expect(result == .noSavedSecret)
        #expect(caller.calls.isEmpty)
        #expect(auth.signedInTokens.isEmpty)
    }

    @Test func recoverySignsInWithServerCustomToken() async throws {
        let secret = Data(repeating: 7, count: 32)
        let store = GuestRecoverySecretStoreStub(secret: secret)
        let caller = GuestRecoveryCallerStub(responses: [["customToken": "firebase-custom-token"]])
        let auth = GuestRecoveryAuthenticatorStub(userID: "new-guest", isAnonymous: true)
        let coordinator = GuestRecoveryCoordinator(
            secretStore: store,
            caller: caller,
            authenticator: auth
        )

        let result = try await coordinator.recoverCurrentGuestIfAvailable()

        #expect(result == .recovered)
        #expect(caller.calls.count == 1)
        #expect(caller.calls[0].name == "recoverGuestAccount")
        #expect(caller.calls[0].payload["recoverySecret"] as? String == secret.base64EncodedString())
        #expect(auth.signedInTokens == ["firebase-custom-token"])
    }

    @Test func recoveryNeverReplacesLinkedAccount() async throws {
        let store = GuestRecoverySecretStoreStub(secret: Data(repeating: 1, count: 32))
        let caller = GuestRecoveryCallerStub()
        let auth = GuestRecoveryAuthenticatorStub(userID: "linked-user", isAnonymous: false)
        let coordinator = GuestRecoveryCoordinator(
            secretStore: store,
            caller: caller,
            authenticator: auth
        )

        let result = try await coordinator.recoverCurrentGuestIfAvailable()

        #expect(result == .skippedNonAnonymousAccount)
        #expect(caller.calls.isEmpty)
        #expect(auth.signedInTokens.isEmpty)
    }

    @Test func malformedRecoveryResponseDoesNotChangeAuthentication() async throws {
        let store = GuestRecoverySecretStoreStub(secret: Data(repeating: 2, count: 32))
        let caller = GuestRecoveryCallerStub(responses: [[:]])
        let auth = GuestRecoveryAuthenticatorStub(userID: "new-guest", isAnonymous: true)
        let coordinator = GuestRecoveryCoordinator(
            secretStore: store,
            caller: caller,
            authenticator: auth
        )

        await #expect(throws: GuestRecoveryError.invalidServerResponse) {
            _ = try await coordinator.recoverCurrentGuestIfAvailable()
        }
        #expect(auth.signedInTokens.isEmpty)
    }

    @Test func revocationDeletesSecretOnlyAfterServerSuccess() async throws {
        let store = GuestRecoverySecretStoreStub(secret: Data(repeating: 3, count: 32))
        let caller = GuestRecoveryCallerStub()
        let auth = GuestRecoveryAuthenticatorStub(userID: "guest-1", isAnonymous: true)
        let coordinator = GuestRecoveryCoordinator(
            secretStore: store,
            caller: caller,
            authenticator: auth
        )

        try await coordinator.revokeCurrentGuestRecovery()

        #expect(caller.calls.map(\.name) == ["revokeGuestRecovery"])
        #expect(store.deleteCount == 1)
        #expect(store.secret == nil)
    }

    @Test func localDiscardDoesNotCallServer() throws {
        let store = GuestRecoverySecretStoreStub(secret: Data(repeating: 4, count: 32))
        let caller = GuestRecoveryCallerStub()
        let auth = GuestRecoveryAuthenticatorStub(userID: "linked-user", isAnonymous: false)
        let coordinator = GuestRecoveryCoordinator(
            secretStore: store,
            caller: caller,
            authenticator: auth
        )

        try coordinator.discardLocalSecret()

        #expect(store.deleteCount == 1)
        #expect(store.secret == nil)
        #expect(caller.calls.isEmpty)
    }
}

private final class GuestRecoverySecretStoreStub: GuestRecoverySecretStoring {
    var secret: Data?
    var createCount = 0
    var generatedSecretCount = 0
    var deleteCount = 0

    init(secret: Data? = nil) {
        self.secret = secret
    }

    func loadSecret() throws -> Data? { secret }

    func createSecretIfNeeded() throws -> Data {
        createCount += 1
        if let secret { return secret }
        let generated = Data(repeating: 9, count: 32)
        secret = generated
        generatedSecretCount += 1
        return generated
    }

    func deleteSecret() throws {
        deleteCount += 1
        secret = nil
    }
}

private final class GuestRecoveryCallerStub: GuestRecoveryCalling {
    struct Call {
        let name: String
        let payload: [String: Any]
    }

    var calls: [Call] = []
    var responses: [[String: Any]]

    init(responses: [[String: Any]] = [[:], [:]]) {
        self.responses = responses
    }

    func call(function name: String, payload: [String: Any]) async throws -> [String: Any] {
        calls.append(Call(name: name, payload: payload))
        return responses.isEmpty ? [:] : responses.removeFirst()
    }
}

@MainActor
private final class GuestRecoveryAuthenticatorStub: GuestRecoveryAuthenticating {
    let currentUserID: String?
    let isCurrentUserAnonymous: Bool
    var signedInTokens: [String] = []

    init(userID: String?, isAnonymous: Bool) {
        currentUserID = userID
        isCurrentUserAnonymous = isAnonymous
    }

    func signIn(customToken: String) async throws {
        signedInTokens.append(customToken)
    }
}
