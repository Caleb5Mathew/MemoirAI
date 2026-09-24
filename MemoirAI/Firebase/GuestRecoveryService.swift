import Foundation
import FirebaseAuth
import FirebaseFunctions
import Security

enum GuestRecoveryCallableContract {
    static let protocolVersion = 1
    static let recoverySecretKey = "recoverySecret"
    static let protocolVersionKey = "protocolVersion"
    static let customTokenKey = "customToken"

    static let enrollFunction = "enrollGuestRecovery"
    static let recoverFunction = "recoverGuestAccount"
    static let revokeFunction = "revokeGuestRecovery"

    static func request(secret: Data) -> [String: Any] {
        [
            recoverySecretKey: secret.base64EncodedString(),
            protocolVersionKey: protocolVersion
        ]
    }
}

enum GuestRecoveryError: LocalizedError, Equatable {
    case keychainFailure(OSStatus)
    case invalidStoredSecret
    case notAnonymous
    case notAuthenticated
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            return "Guest recovery storage failed. (\(status))"
        case .invalidStoredSecret:
            return "The saved guest recovery key is invalid."
        case .notAnonymous:
            return "Guest recovery is only available for anonymous accounts."
        case .notAuthenticated:
            return "A temporary account is required before guest recovery can run."
        case .invalidServerResponse:
            return "The guest recovery service returned an invalid response."
        }
    }
}

protocol GuestRecoverySecretStoring {
    func loadSecret() throws -> Data?
    func createSecretIfNeeded() throws -> Data
    func deleteSecret() throws
}

protocol GuestRecoveryCalling {
    func call(function name: String, payload: [String: Any]) async throws -> [String: Any]
}

@MainActor
protocol GuestRecoveryAuthenticating {
    var currentUserID: String? { get }
    var isCurrentUserAnonymous: Bool { get }
    func signIn(customToken: String) async throws
}

struct ICloudKeychainGuestRecoverySecretStore: GuestRecoverySecretStoring {
    static let secretByteCount = 32

    private let service: String
    private let account: String

    init(
        service: String = "com.Buildr.MemoirAI.guest-recovery",
        account: String = "guest-recovery-secret-v1"
    ) {
        self.service = service
        self.account = account
    }

    func loadSecret() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw GuestRecoveryError.keychainFailure(status)
        }
        guard let secret = result as? Data,
              secret.count == Self.secretByteCount else {
            throw GuestRecoveryError.invalidStoredSecret
        }
        return secret
    }

    func createSecretIfNeeded() throws -> Data {
        if let existing = try loadSecret() { return existing }

        var bytes = [UInt8](repeating: 0, count: Self.secretByteCount)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw GuestRecoveryError.keychainFailure(randomStatus)
        }
        let secret = Data(bytes)

        var attributes = baseQuery
        attributes[kSecValueData as String] = secret
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem,
           let existing = try loadSecret() {
            return existing
        }
        guard addStatus == errSecSuccess else {
            throw GuestRecoveryError.keychainFailure(addStatus)
        }
        return secret
    }

    func deleteSecret() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GuestRecoveryError.keychainFailure(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true
        ]
    }
}

struct FirebaseGuestRecoveryCaller: GuestRecoveryCalling {
    func call(function name: String, payload: [String: Any]) async throws -> [String: Any] {
        let result = try await Functions.functions().httpsCallable(name).call(payload)
        guard let response = result.data as? [String: Any] else {
            throw GuestRecoveryError.invalidServerResponse
        }
        return response
    }
}

@MainActor
struct FirebaseGuestRecoveryAuthenticator: GuestRecoveryAuthenticating {
    var currentUserID: String? { Auth.auth().currentUser?.uid }
    var isCurrentUserAnonymous: Bool { Auth.auth().currentUser?.isAnonymous == true }

    func signIn(customToken: String) async throws {
        _ = try await Auth.auth().signIn(withCustomToken: customToken)
    }
}

enum GuestRecoveryAttemptResult: Equatable {
    case noSavedSecret
    case skippedNonAnonymousAccount
    case recovered
}

@MainActor
final class GuestRecoveryCoordinator {
    static let shared = GuestRecoveryCoordinator()

    private let secretStore: GuestRecoverySecretStoring
    private let caller: GuestRecoveryCalling
    private let authenticator: GuestRecoveryAuthenticating

    convenience init() {
        self.init(
            secretStore: ICloudKeychainGuestRecoverySecretStore(),
            caller: FirebaseGuestRecoveryCaller(),
            authenticator: FirebaseGuestRecoveryAuthenticator()
        )
    }

    init(
        secretStore: GuestRecoverySecretStoring,
        caller: GuestRecoveryCalling,
        authenticator: GuestRecoveryAuthenticating
    ) {
        self.secretStore = secretStore
        self.caller = caller
        self.authenticator = authenticator
    }

    func enrollCurrentGuest() async throws {
        guard authenticator.currentUserID != nil else {
            throw GuestRecoveryError.notAuthenticated
        }
        guard authenticator.isCurrentUserAnonymous else {
            throw GuestRecoveryError.notAnonymous
        }
        let secret = try secretStore.createSecretIfNeeded()
        _ = try await caller.call(
            function: GuestRecoveryCallableContract.enrollFunction,
            payload: GuestRecoveryCallableContract.request(secret: secret)
        )
    }

    func recoverCurrentGuestIfAvailable() async throws -> GuestRecoveryAttemptResult {
        guard authenticator.currentUserID != nil else {
            throw GuestRecoveryError.notAuthenticated
        }
        guard authenticator.isCurrentUserAnonymous else {
            return .skippedNonAnonymousAccount
        }
        guard let secret = try secretStore.loadSecret() else {
            return .noSavedSecret
        }
        let response = try await caller.call(
            function: GuestRecoveryCallableContract.recoverFunction,
            payload: GuestRecoveryCallableContract.request(secret: secret)
        )
        guard let customToken = response[GuestRecoveryCallableContract.customTokenKey] as? String,
              !customToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GuestRecoveryError.invalidServerResponse
        }
        try await authenticator.signIn(customToken: customToken)
        return .recovered
    }

    func revokeCurrentGuestRecovery() async throws {
        guard authenticator.currentUserID != nil else {
            throw GuestRecoveryError.notAuthenticated
        }
        guard let secret = try secretStore.loadSecret() else { return }
        _ = try await caller.call(
            function: GuestRecoveryCallableContract.revokeFunction,
            payload: GuestRecoveryCallableContract.request(secret: secret)
        )
        try secretStore.deleteSecret()
    }

    /// Removes only the device's recovery credential. Use after a guest is linked
    /// to a permanent account or after account deletion has already been confirmed.
    func discardLocalSecret() throws {
        try secretStore.deleteSecret()
    }
}
