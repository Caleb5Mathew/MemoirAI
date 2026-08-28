import Testing
import UserNotifications
@testable import MemoirAI

struct NotificationPermissionPolicyTests {
    @Test func permissionActionsMatchSystemStatus() {
        #expect(NotificationPermissionPolicy.action(for: .notDetermined) == .request)
        #expect(NotificationPermissionPolicy.action(for: .denied) == .openSettings)
        #expect(NotificationPermissionPolicy.action(for: .authorized) == .none)
        #expect(NotificationPermissionPolicy.action(for: .provisional) == .none)
    }
}
