//
//  MemoirAIApp.swift
//  MemoirAI
//

import SwiftUI
import RevenueCat
import Mixpanel
import FBSDKCoreKit
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

// MARK: - UIKit delegate wrapper
final class FBAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // Initialize Firebase FIRST
        FirebaseConfig.shared.configure()

        // Remote push (FCM): family access requests notify the memoir owner.
        // Registration is silent; the user-facing permission prompt stays where it
        // already lives (NotificationManager during onboarding).
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        // The Info.plist defaults keep Meta auto-init and advertiser ID collection off.
        // Apply the current ATT decision before manually starting the SDK so a first
        // launch can never collect advertising identifiers before consent.
        ATTHelper.applyCurrentAuthorizationToFacebook()
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        // ATT controls whether Facebook may use advertising identifiers.
        Settings.shared.isAutoLogAppEventsEnabled = true

        print("✅ FBSDK version:", Settings.shared.sdkVersion)
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] remote notification registration failed: \(error.localizedDescription)")
    }

    // Needed only if you use FB Login / App Links / Google Sign-In
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        if url.scheme == "memoirai" {
            if url.host == "order-complete" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let rawSessionId = components?.queryItems?.first(where: { $0.name == "session_id" })?.value
                if let sessionId = CheckoutReturnPolicy.normalizeSessionID(rawSessionId) {
                    print("[Order] Stripe checkout return received")
                    UserDefaults.standard.set(sessionId, forKey: CheckoutReturnPolicy.pendingSessionDefaultsKey)
                    NotificationCenter.default.post(
                        name: .orderCheckoutReturnReceived,
                        object: nil,
                        userInfo: ["sessionId": sessionId]
                    )
                }
                return true
            }
            if url.host == "order-cancelled" {
                NotificationCenter.default.post(name: .orderCancelled, object: nil)
                return true
            }
            if url.host == "memory" {
                let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if UUID(uuidString: trimmed) != nil {
                    print("[QRDeepLink] AppDelegate forwarding valid memory link")
                    NotificationCenter.default.post(
                        name: .memoirOpenMemoryDeepLink,
                        object: nil,
                        userInfo: ["url": url]
                    )
                }
                // Return false so the system may still deliver the URL to SwiftUI `.onOpenURL` (cold-launch parity).
                return false
            }
            // Unknown custom-scheme host (e.g. join links): do not claim handled — let scene / other handlers see it.
            return false
        }
        if GIDSignIn.sharedInstance.handle(url) { return true }
        return ApplicationDelegate.shared.application(app, open: url, options: options)
    }
}

extension FBAppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        PushTokenService.shared.updateToken(fcmToken)
    }
}

extension FBAppDelegate: UNUserNotificationCenterDelegate {
    /// Show pushes as banners while the app is foregrounded (access requests are
    /// actionable immediately via the Home banner).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

extension Notification.Name {
    static let orderCheckoutReturnReceived = Notification.Name("orderCheckoutReturnReceived")
    static let orderCheckoutVerificationFailed = Notification.Name("orderCheckoutVerificationFailed")
    static let orderCheckoutFinalizing = Notification.Name("orderCheckoutFinalizing")
    static let orderComplete = Notification.Name("orderComplete")
    static let orderCancelled = Notification.Name("orderCancelled")
    static let bookCoverBackfillComplete = Notification.Name("bookCoverBackfillComplete")
    static let memoriesHydratedFromFirestore = Notification.Name("memoriesHydratedFromFirestore")
    /// iOS is about to suspend; flush partial generation state to disk (see `StorybookGenerationBackgroundTask`).
    static let storybookGenerationBackgroundExpiring = Notification.Name("storybookGenerationBackgroundExpiring")
    /// `userInfo["bookSyncCountDelta"]` as `Int` (+1 / -1) — refcount for concurrent `queueBookSync` (legacy `isUploading` still accepted).
    static let storybookCloudUploadActivity = Notification.Name("storybookCloudUploadActivity")
    /// `userInfo["profileId"]` as `String` (UUID) when a generation resume marker is cleared.
    static let generationProgressMarkerChanged = Notification.Name("generationProgressMarkerChanged")
    /// Navigate to `StoryPage` for cloud storybook generation (banner tap / secondary affordance).
    static let navigateToCloudStorybookGeneration = Notification.Name("memoirai.navigateToCloudStorybookGeneration")
    /// Posted from `FBAppDelegate` for `memoirai://memory/{UUID}` so `ContentView` can route even when `.onOpenURL` is late on cold launch.
    static let memoirOpenMemoryDeepLink = Notification.Name("memoirai.openMemoryDeepLink")
}

@main
struct MemoirAIApp: App {
    @StateObject private var profileVM = ProfileViewModel()
    @State private var checkoutSessionBeingVerified: String?
    
    let persistenceController = PersistenceController.shared

    @UIApplicationDelegateAdaptor(FBAppDelegate.self) var fbDelegate

    init() {
        let rcUserDefaultsKey = "memoirai_rc_user_id"
        let uuid = UserDefaults.standard.string(forKey: rcUserDefaultsKey) ?? {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: rcUserDefaultsKey)
            return newID
        }()

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
           !apiKey.isEmpty {
            Purchases.configure(withAPIKey: apiKey, appUserID: uuid)
            print("RevenueCat configured")

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard Purchases.isConfigured else { return }
                await RCSubscriptionManager.shared.refreshCustomerInfo()
            }
        } else {
            print("❌ RevenueCat API key not found in Info.plist")
        }

        // ─ Mixpanel ───────────────────────────────────────────────
        Mixpanel.initialize(token: "6437139af64d0541c2a8a8e5157ae72f",
                            trackAutomaticEvents: true)
        Mixpanel.mainInstance().track(event: "App Launched")

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            Mixpanel.mainInstance().track(event: "First Launch")
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileVM)
                .environmentObject(iCloudManager.shared)
                .environmentObject(RCSubscriptionManager.shared)
                .environmentObject(TutorialCoordinator.shared)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                // Our custom UI uses light backgrounds; force a light appearance so dynamic text stays dark
                .preferredColorScheme(.light)
                .onAppear {
                    GenerationProgressMarker.clearStaleOnLaunchIfNeeded()
                    Haptics.warmUp()
                }
                .task {
                    await verifyPendingCheckoutReturnIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: .orderCheckoutReturnReceived)) { notification in
                    guard let sessionId = notification.userInfo?["sessionId"] as? String else { return }
                    Task { await verifyCheckoutReturn(sessionId: sessionId) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    PermissionManager.shared.handleAppDidBecomeActive()
                    Task { @MainActor in
                        guard Purchases.isConfigured else { return }
                        await RCSubscriptionManager.shared.refreshCustomerInfo()
                    }
                    Task {
                        await profileVM.retryPendingProfileMutations()
                        await FirestoreSyncService.shared.retryPendingSyncs(for: profileVM.selectedProfile.id)
                        await verifyPendingCheckoutReturnIfNeeded()
                    }
                }
        }
    }

    @MainActor
    private func verifyPendingCheckoutReturnIfNeeded() async {
        guard let sessionId = UserDefaults.standard.string(
            forKey: CheckoutReturnPolicy.pendingSessionDefaultsKey
        ) else { return }
        await verifyCheckoutReturn(sessionId: sessionId)
    }

    @MainActor
    private func verifyCheckoutReturn(sessionId: String) async {
        guard let normalized = CheckoutReturnPolicy.normalizeSessionID(sessionId) else {
            UserDefaults.standard.removeObject(forKey: CheckoutReturnPolicy.pendingSessionDefaultsKey)
            NotificationCenter.default.post(name: .orderCheckoutVerificationFailed, object: nil)
            return
        }
        guard checkoutSessionBeingVerified != normalized else { return }
        checkoutSessionBeingVerified = normalized
        defer { checkoutSessionBeingVerified = nil }

        do {
            let verification = try await OrderService.shared.verifyCheckoutReturn(sessionId: normalized)
            guard verification.verified else {
                if verification.isFinalizingPaidOrder {
                    NotificationCenter.default.post(name: .orderCheckoutFinalizing, object: nil)
                    return
                }
                NotificationCenter.default.post(name: .orderCheckoutVerificationFailed, object: nil)
                return
            }
            UserDefaults.standard.removeObject(forKey: CheckoutReturnPolicy.pendingSessionDefaultsKey)
            OrderCartStore.shared.clear()
            NotificationCenter.default.post(
                name: .orderComplete,
                object: nil,
                userInfo: ["sessionId": normalized]
            )
        } catch {
            NotificationCenter.default.post(name: .orderCheckoutVerificationFailed, object: nil)
        }
    }
}
