import AVFoundation
import Foundation
import Speech

@MainActor
final class OnboardingRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var liveCaptionEnded = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var liveTranscript = ""
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalizationTask: Task<Void, Never>?
    private var recordingID = UUID()
    private var permissionRequestID = UUID()
    private var hasInputTap = false
    private(set) var audioURL: URL?

    func requestPermissionsAndStart() {
        guard !isRecording, !isFinalizing else { return }
        guard CloudTranscriptionDisclosure.isAccepted() else {
            errorMessage = CloudTranscriptionDisclosure.message
            return
        }
        let permissionID = UUID()
        permissionRequestID = permissionID
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self, self.permissionRequestID == permissionID else { return }
                guard granted else {
                    self.errorMessage = "Allow microphone access in Settings to record a memory. You can also type your story."
                    return
                }
                SFSpeechRecognizer.requestAuthorization { status in
                    Task { @MainActor in
                        guard self.permissionRequestID == permissionID else { return }
                        guard status == .authorized else {
                            self.errorMessage = "Allow speech recognition in Settings, or type your story instead."
                            return
                        }
                        self.start()
                    }
                }
            }
        }
    }

    func start() {
        guard !isRecording, !isFinalizing else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        do {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
                throw OnboardingRecorderError.couldNotStart
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            recorder.delegate = self
            self.recorder = recorder
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.engine = engine
            self.request = request
            let id = UUID()
            recordingID = id
            liveTranscript = ""
            liveCaptionEnded = false
            errorMessage = nil
            elapsed = 0
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.recordingID == id else { return }
                    if let result { self.liveTranscript = result.bestTranscription.formattedString }
                    if result?.isFinal == true || error != nil {
                        self.liveCaptionEnded = true
                        // Speech recognition has a shorter lifetime than the audio recording.
                        // Cloud transcription reads the complete recording after the user stops.
                        self.completeFinalization()
                    }
                }
            }
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: engine.inputNode.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            hasInputTap = true
            try engine.start()
            guard recorder.record(forDuration: RecordingDurationPolicy.maximumRecordingDuration) else {
                throw OnboardingRecorderError.couldNotStart
            }
            audioURL = url
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.elapsed = self.recorder?.currentTime ?? self.elapsed
                    if self.recorder?.isRecording != true { _ = self.stop() }
                }
            }
        } catch {
            _ = stop()
            completeFinalization()
            recorder?.stop()
            recorder = nil
            try? FileManager.default.removeItem(at: url)
            errorMessage = "Memoir couldn’t start the microphone. Check Settings and try again."
        }
    }

    @discardableResult
    func stop() -> String {
        permissionRequestID = UUID()
        guard isRecording else { return liveTranscript }
        elapsed = recorder?.currentTime ?? elapsed
        isRecording = false
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        stopAudioEngine()
        request?.endAudio()
        guard recognitionTask != nil else {
            completeFinalization()
            return liveTranscript
        }
        isFinalizing = true
        finalizationTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            self?.completeFinalization()
        }
        return liveTranscript
    }

    func finish() async -> String {
        _ = stop()
        while isFinalizing {
            do { try await Task.sleep(nanoseconds: 20_000_000) } catch { break }
        }
        return liveTranscript
    }

    private func completeFinalization() {
        finalizationTask?.cancel()
        finalizationTask = nil
        recordingID = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        request?.endAudio()
        request = nil
        stopAudioEngine()
        isFinalizing = false
        if !isRecording {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    private func stopAudioEngine() {
        engine?.stop()
        if hasInputTap {
            engine?.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        engine = nil
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            _ = self.stop()
            if !flag { self.errorMessage = "Recording stopped unexpectedly. Your recorded audio has been kept." }
        }
    }

    func discard() {
        _ = stop()
        completeFinalization()
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
        recorder = nil
        elapsed = 0
        liveTranscript = ""
        liveCaptionEnded = false
    }
}

enum OnboardingRecorderError: Error {
    case couldNotStart
}
