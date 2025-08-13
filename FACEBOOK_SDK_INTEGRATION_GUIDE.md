# Facebook SDK Integration Guide

This guide documents the complete Facebook SDK integration setup for iOS apps, specifically designed for apps that need Facebook Analytics, App Tracking Transparency (ATT), and RevenueCat integration for subscription attribution.

## 📋 Overview

This integration provides:
- **Facebook Analytics** for conversion tracking
- **App Tracking Transparency (ATT)** compliance
- **RevenueCat integration** for subscription attribution
- **SKAdNetwork** support for iOS 14+ privacy
- **Deep linking** support (if needed)

## 🏗 Architecture Components

### 1. Core Files
- `MemoirAIApp.swift` - Main app delegate with Facebook SDK initialization
- `ATTHelper.swift` - App Tracking Transparency management
- `FacebookAnalytics.swift` - Custom analytics events
- `Info.plist` - Configuration and permissions
- `project.pbxproj` - Dependencies and build settings

### 2. Integration Points
- **App Launch** - Facebook SDK initialization
- **ATT Permission** - User tracking consent
- **Analytics Events** - Custom conversion tracking
- **RevenueCat** - Server-side purchase attribution

## 📦 Dependencies Setup

### Swift Package Manager Dependencies

Add these to your Xcode project via **File → Add Package Dependencies**:

```swift
// Facebook iOS SDK
Repository: https://github.com/facebook/facebook-ios-sdk.git
Version: Up to next major version 14.1.0

// Required Products:
- FacebookAEM
- FacebookBasics  
- FacebookCore
- FacebookGamingServices
- FacebookLogin
- FacebookShare
```

### Manual Package Dependencies (project.pbxproj)

If you need to manually configure, add these to your project:

```xml
<!-- XCRemoteSwiftPackageReference -->
<key>84063F052E00E29200218E1F</key>
<dict>
    <key>isa</key>
    <string>XCRemoteSwiftPackageReference</string>
    <key>repositoryURL</key>
    <string>https://github.com/facebook/facebook-ios-sdk.git</string>
    <key>requirement</key>
    <dict>
        <key>kind</key>
        <string>upToNextMajorVersion</string>
        <key>minimumVersion</key>
        <string>14.1.0</string>
    </dict>
</dict>

<!-- XCSwiftPackageProductDependency entries for each product -->
```

## ⚙️ Info.plist Configuration

### Required Facebook Keys

```xml
<!-- Facebook App Configuration -->
<key>FacebookAppID</key>
<string>YOUR_FACEBOOK_APP_ID</string>

<key>FacebookDisplayName</key>
<string>Your App Name</string>

<key>FacebookAutoInitEnabled</key>
<true/>

<key>FacebookAutoLogAppEventsEnabled</key>
<true/>

<key>FacebookClientToken</key>
<string>YOUR_CLIENT_TOKEN</string>

<key>FacebookAdvertiserIDCollectionEnabled</key>
<true/>
```

### URL Schemes

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.yourcompany.yourapp</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourappscheme</string>
            <string>fbYOUR_FACEBOOK_APP_ID</string>
        </array>
    </dict>
</array>
```

### LSApplicationQueriesSchemes

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>fbapi</string>
    <string>fbapi20230405</string>
    <string>fbauth2</string>
    <string>fbshareextension</string>
</array>
```

### SKAdNetwork Identifiers

```xml
<key>SKAdNetworkItems</key>
<array>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>cstr6suwn9.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>4fzdc2evr5.skadnetwork</string>
    </dict>
    <!-- Add more Facebook SKAdNetwork identifiers as needed -->
</array>
```

### Privacy Permissions

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This allows us to provide you with better ads and understand which ads lead to subscriptions, helping us improve our service.</string>
```

## 🚀 App Delegate Setup

### Main App File (YourApp.swift)

```swift
import SwiftUI
import RevenueCat
import FBSDKCoreKit

// MARK: - UIKit delegate wrapper
final class FBAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // Initialize Facebook SDK
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        // Configure Facebook tracking
        Settings.shared.isAutoLogAppEventsEnabled = true
        // Note: isAdvertiserTrackingEnabled managed by ATTHelper

        print("✅ FBSDK version:", Settings.shared.sdkVersion)
        return true
    }

    // Handle deep links (if needed)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        return ApplicationDelegate.shared.application(app, open: url, options: options)
    }
}

@main
struct YourApp: App {
    
    // Tell SwiftUI to install the delegate
    @UIApplicationDelegateAdaptor(FBAppDelegate.self) var fbDelegate

    init() {
        // Configure RevenueCat with stable user ID for Facebook attribution
        let rcUserDefaultsKey = "yourapp_rc_user_id"
        let uuid = UserDefaults.standard.string(forKey: rcUserDefaultsKey) ?? {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: rcUserDefaultsKey)
            return newID
        }()

        // Configure RevenueCat FIRST
        Purchases.logLevel = .debug
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
           !apiKey.isEmpty {
            Purchases.configure(withAPIKey: apiKey, appUserID: uuid)
            print("✅ RevenueCat configured with userID: \(uuid)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## 📊 ATT Helper Implementation

### ATTHelper.swift

```swift
import SwiftUI
import AppTrackingTransparency
import FBSDKCoreKit

class ATTHelper: ObservableObject {
    @Published var trackingStatus: ATTrackingManager.AuthorizationStatus = .notDetermined
    
    static let shared = ATTHelper()
    
    private init() {
        trackingStatus = ATTrackingManager.trackingAuthorizationStatus
    }
    
    /// Request tracking permission for high-quality Facebook ad attribution
    func requestTrackingPermission() {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            updateFacebookTracking()
            return
        }
        
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.trackingStatus = status
                self?.updateFacebookTracking()
            }
        }
    }
    
    /// Update Facebook SDK tracking based on ATT status
    private func updateFacebookTracking() {
        let isAuthorized = trackingStatus == .authorized
        Settings.shared.isAdvertiserTrackingEnabled = isAuthorized
        
        print("📊 ATT Status: \(trackingStatus.rawValue), FB Tracking: \(isAuthorized)")
    }
    
    /// Check if we should show ATT prompt
    var shouldShowATTPrompt: Bool {
        trackingStatus == .notDetermined
    }
}
```

## 📈 Analytics Implementation

### FacebookAnalytics.swift

```swift
import Foundation
import FBSDKCoreKit

/// Facebook Analytics helper for tracking conversion events
/// This enables attribution of Facebook ads to actual subscription conversions
class FacebookAnalytics {
    
    /// Log when user views the paywall (conversion funnel start)
    static func logPaywallViewed() {
        AppEvents.shared.logEvent(AppEvents.Name("paywall_viewed"))
        print("📊 FB: Paywall viewed")
    }
    
    /// Log when user initiates checkout process
    static func logCheckoutInitiated() {
        AppEvents.shared.logEvent(AppEvents.Name("checkout_initiated"))
        print("📊 FB: Checkout initiated")
    }
    
    /// Log when user starts free trial
    static func logTrialStarted(price: Double = 0.0, currency: String = "USD") {
        AppEvents.shared.logEvent(AppEvents.Name("trial_started"), valueToSum: price)
        print("📊 FB: Trial started - \(currency)\(price)")
    }
    
    /// Log when user completes onboarding (engagement signal)
    static func logOnboardingCompleted() {
        AppEvents.shared.logEvent(AppEvents.Name("onboarding_completed"))
        print("📊 FB: Onboarding completed")
    }
    
    /// Log when user creates their first memory (engagement signal)
    static func logFirstMemoryCreated() {
        AppEvents.shared.logEvent(AppEvents.Name("first_memory_created"))
        print("📊 FB: First memory created")
    }
}
```

## 🔗 ContentView Integration

### ContentView.swift

```swift
import SwiftUI
import FBSDKCoreKit

struct ContentView: View {
    var body: some View {
        // Your main app content
        MainView()
        .onAppear {
            // 🎯 CRITICAL: Establish link between ad clicks and app opens
            AppEvents.shared.activateApp()
        }
    }
}
```

## 💰 RevenueCat Integration

### SubscriptionManager.swift

```swift
import Foundation
import RevenueCat
import SwiftUI

@MainActor
final class RCSubscriptionManager: NSObject, ObservableObject {
    static let shared = RCSubscriptionManager()
    
    // ... your subscription logic ...

    func purchase(package: Package) async throws {
        // 🎯 Track checkout initiation for Facebook
        FacebookAnalytics.logCheckoutInitiated()
        
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            print("Purchase cancelled by user.")
            return
        }
        
        print("Purchase successful. Refreshing customer info.")
        evaluateEntitlements(from: result.customerInfo)
        
        // ✅ RevenueCat handles purchase events server-side via Conversions API
        // No client-side purchase logging needed to avoid duplicates
    }
}
```

## 🎯 Onboarding Flow Integration

### OnboardingFlow.swift

```swift
import SwiftUI

struct OnboardingFlow: View {
    @StateObject private var attHelper = ATTHelper.shared
    @State private var showPaywall = false
    
    var body: some View {
        // Your onboarding content
        
        Button("Continue") {
            // Complete onboarding
            completeOnboarding()
            
            // 🎯 Track onboarding completion for Facebook
            FacebookAnalytics.logOnboardingCompleted()
            
            // 🎯 Request ATT permission before paywall for optimal ad attribution
            if attHelper.shouldShowATTPrompt {
                attHelper.requestTrackingPermission()
                // Small delay to let ATT prompt complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showPaywall = true
                }
            } else {
                showPaywall = true
            }
        }
    }
}
```

## 🔧 Facebook Developer Console Setup

### 1. Create Facebook App
1. Go to [Facebook Developers](https://developers.facebook.com/)
2. Create a new app or use existing one
3. Add iOS platform to your app

### 2. Configure iOS Settings
- **Bundle ID**: `com.yourcompany.yourapp`
- **App Store ID**: Your App Store ID (when published)
- **iPhone Store ID**: Same as App Store ID
- **iPad Store ID**: Same as App Store ID

### 3. Get Required Keys
- **App ID**: Found in your app's dashboard
- **Client Token**: Found in app settings → Advanced
- **App Secret**: Found in app settings → Basic

### 4. Configure Events
In Facebook Events Manager:
1. Create custom events for your conversion funnel
2. Set up conversion tracking
3. Configure RevenueCat integration (if using)

## 📱 Testing & Debugging

### Debug Logs
Enable debug logging in your app:

```swift
// In your app delegate
print("✅ FBSDK version:", Settings.shared.sdkVersion)

// In ATTHelper
print("📊 ATT Status: \(trackingStatus.rawValue), FB Tracking: \(isAuthorized)")

// In FacebookAnalytics
print("📊 FB: [Event Name]")
```

### Testing Checklist
- [ ] Facebook SDK initializes without errors
- [ ] ATT permission prompt appears
- [ ] Analytics events are logged
- [ ] RevenueCat integration works
- [ ] Deep links work (if implemented)
- [ ] SKAdNetwork events are tracked

## 🚨 Common Issues & Solutions

### Issue: Facebook SDK not initializing
**Solution**: Check Info.plist configuration and ensure all required keys are present

### Issue: ATT prompt not appearing
**Solution**: Ensure `NSUserTrackingUsageDescription` is set in Info.plist

### Issue: Analytics events not tracking
**Solution**: Verify Facebook App ID and Client Token are correct

### Issue: RevenueCat attribution not working
**Solution**: Ensure stable user ID is passed to RevenueCat configuration

## 📚 Additional Resources

- [Facebook iOS SDK Documentation](https://developers.facebook.com/docs/ios/)
- [App Tracking Transparency Guide](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [RevenueCat Facebook Integration](https://docs.revenuecat.com/docs/facebook-ads)
- [SKAdNetwork Documentation](https://developer.apple.com/documentation/storekit/skadnetwork)

## 🔄 Migration Checklist

When setting up a new app with this integration:

1. **Dependencies**: Add Facebook iOS SDK via SPM
2. **Info.plist**: Configure all required keys and permissions
3. **App Delegate**: Implement FBAppDelegate wrapper
4. **ATT Helper**: Add ATTHelper class
5. **Analytics**: Create FacebookAnalytics class
6. **RevenueCat**: Configure with stable user ID
7. **Facebook Console**: Set up app and events
8. **Testing**: Verify all components work together

## 📊 Event Tracking Strategy

### Conversion Funnel Events
1. `paywall_viewed` - User sees subscription options
2. `checkout_initiated` - User starts purchase process
3. `trial_started` - User begins free trial
4. `onboarding_completed` - User finishes onboarding
5. `first_memory_created` - User creates first content

### Best Practices
- **Don't duplicate events**: Let RevenueCat handle purchase events server-side
- **Use consistent naming**: Follow Facebook's event naming conventions
- **Include value parameters**: Add monetary values where applicable
- **Test thoroughly**: Verify events in Facebook Events Manager

This integration provides a robust foundation for Facebook advertising attribution and analytics in iOS apps with subscription models. 