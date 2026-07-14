//
//  AudioSessionInterruptionObserver.swift
//  MemoirAI
//
//  Shared helper so every recording surface reacts the same way to phone calls,
//  Siri, route changes, and backgrounding instead of silently leaving the UI
//  in a "recording" state while nothing is actually being captured.
//

import Foundation
import AVFoundation
import UIKit

/// Observes `AVAudioSession` interruptions/route changes and app backgrounding,
/// and forwards them as simple callbacks. This class never touches an
/// `AVAudioRecorder` directly — each recording screen owns its own recorder and
/// is responsible for pausing it (by reusing its existing pause path) when one
/// of these callbacks fires while actively recording.
///
/// Usage: hold one instance per recording view as a `@StateObject`, assign the
/// callbacks in `.onAppear`, and let it live for the lifetime of the view.
/// Observers are removed automatically in `deinit`.
final class AudioSessionInterruptionObserver: ObservableObject {
    /// The system began an interruption (phone call, Siri, alarm, etc.). The
    /// recorder is definitely not capturing audio anymore at this point.
    var onInterruptionBegan: (() -> Void)?

    /// The interruption ended. `shouldResume` mirrors `AVAudioSession`'s
    /// `.shouldResume` option. Callers must NOT auto-resume recording from this
    /// callback — only surface/keep the existing "paused" UI so the user can
    /// explicitly tap Resume.
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?

    /// The active input/output route disappeared (e.g. Bluetooth or wired
    /// headphones were unplugged mid-recording).
    var onRouteChangeDeviceUnavailable: (() -> Void)?

    /// The app is about to enter the background.
    var onAppBackgrounded: (() -> Void)?

    private var tokens: [NSObjectProtocol] = []
    private let center = NotificationCenter.default

    init() {
        tokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        })

        tokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        })

        tokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onAppBackgrounded?()
        })
    }

    deinit {
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            var shouldResume = false
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            }
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard
            let info = note.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
            reason == .oldDeviceUnavailable
        else { return }

        onRouteChangeDeviceUnavailable?()
    }
}
