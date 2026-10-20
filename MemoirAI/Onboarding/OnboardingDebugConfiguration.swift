import UIKit
import AVFoundation

/// Temporary testing switches are compiled out of distribution builds.
enum OnboardingDebugConfiguration {
    static var replayOnLaunch: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var simulatorHeadshot: UIImage? {
        #if DEBUG && targetEnvironment(simulator)
        return UIImage(named: "AlexOnboardingPortrait")
        #else
        return nil
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    struct AudioFixture {
        let url: URL
        let draftTranscript: String
    }

    static func audioFixtureRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-onboarding-audio-fixture")
    }

    /// Decodes the bundled narration into the same AAC container used by the recorder.
    /// Readiness and the finished transcript still come from the real cloud workflow.
    static func loadAudioFixture() async throws -> AudioFixture {
        guard let source = Bundle.main.url(forResource: "alex-sample", withExtension: "mp3") else {
            throw AudioFixtureError.missingSample
        }
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("onboarding-audio-fixture-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioFixtureError.cannotExport
        }
        exporter.outputURL = output
        exporter.outputFileType = .m4a
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw exporter.error ?? AudioFixtureError.cannotExport
        }
        let byteCount = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard byteCount > 0 else {
            try? FileManager.default.removeItem(at: output)
            throw AudioFixtureError.cannotExport
        }
        return AudioFixture(
            url: output,
            draftTranscript: "Dad brought the radio to the kitchen table and asked me to hold the torch. I must have been about eight."
        )
    }

    enum AudioFixtureError: LocalizedError {
        case missingSample, cannotExport

        var errorDescription: String? {
            switch self {
            case .missingSample: return "The simulator audio fixture is missing from the app bundle."
            case .cannotExport: return "The simulator audio fixture could not be converted to a recording."
            }
        }
    }
    #endif

}
