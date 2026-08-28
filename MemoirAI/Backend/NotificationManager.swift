import Foundation
import UserNotifications

enum NotificationPermissionAction: Equatable {
    case request
    case openSettings
    case none
}

enum NotificationPermissionPolicy {
    static func action(for status: UNAuthorizationStatus) -> NotificationPermissionAction {
        switch status {
        case .notDetermined:
            return .request
        case .denied:
            return .openSettings
        case .authorized, .provisional, .ephemeral:
            return .none
        @unknown default:
            return .none
        }
    }
}

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            self?.refreshAuthorizationStatus()
            if granted {
                print("✅ Notification permission granted")
            } else if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleDailyPrompt() {
        let content = UNMutableNotificationContent()
        content.title = "Your Daily Story Prompt"
        content.body = "Ready to share another memory? Tap to record your story."
        content.sound = .default
        
        // Schedule for 7 PM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 19
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "dailyPrompt", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("✅ Daily prompt notification scheduled")
            }
        }
    }
    
    func scheduleWeeklyReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Continue Your Memoir"
        content.body = "You haven't recorded any stories this week. Your family would love to hear from you!"
        content.sound = .default
        
        // Schedule for Sunday at 10 AM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 10
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "weeklyReminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling weekly reminder: \(error.localizedDescription)")
            } else {
                print("✅ Weekly reminder notification scheduled")
            }
        }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
