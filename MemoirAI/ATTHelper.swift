//
//  ATTHelper.swift
//  MemoirAI
//
//  Created by user941803 on 7/7/25.
//


import SwiftUIimport AppTrackingTransparencyimport FBSDKCoreKitclass ATTHelper: ObservableObject {    @Published var trackingStatus: ATTrackingManager.AuthorizationStatus = .notDetermined        static let shared = ATTHelper()        private init() {        trackingStatus = ATTrackingManager.trackingAuthorizationStatus    }        /// Request tracking permission for high-quality Facebook ad attribution    func requestTrackingPermission() {        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {            updateFacebookTracking()            return        }                ATTrackingManager.requestTrackingAuthorization { [weak self] status in            DispatchQueue.main.async {                self?.trackingStatus = status                self?.updateFacebookTracking()            }        }    }        /// Update Facebook SDK tracking based on ATT status    private func updateFacebookTracking() {        let isAuthorized = trackingStatus == .authorized        Settings.shared.isAdvertiserTrackingEnabled = isAuthorized                print("📊 ATT Status: \(trackingStatus.rawValue), FB Tracking: \(isAuthorized)")    }        /// Check if we should show ATT prompt    var shouldShowATTPrompt: Bool {        trackingStatus == .notDetermined    }} 