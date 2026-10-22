import AVFoundation
import Foundation
import Testing
@testable import MemoirAI

@Suite(.serialized)
struct InterviewAudioProcessorTests {
    @Test func interviewModeRequiresDeveloperAccessAndProfileOptIn() {
        #expect(InterviewAudioPolicy.shouldProcess(isDeveloperUnlocked: true, isEnabledForProfile: true))
        #expect(!InterviewAudioPolicy.shouldProcess(isDeveloperUnlocked: false, isEnabledForProfile: true))
        #expect(!InterviewAudioPolicy.shouldProcess(isDeveloperUnlocked: true, isEnabledForProfile: false))
    }

    @Test func gainTargetsQuietSpeechWithoutExceedingNineDecibels() {
        #expect(InterviewAudioPolicy.gainDecibels(inputRMSDecibels: -42) == 9)
        #expect(InterviewAudioPolicy.gainDecibels(inputRMSDecibels: -25) == 5)
        #expect(InterviewAudioPolicy.gainDecibels(inputRMSDecibels: -18) == 0)
        #expect(InterviewAudioPolicy.gainDecibels(inputRMSDecibels: .nan) == 0)
    }

    @Test func limiterRaisesQuietSamplesAndKeepsPeaksBelowCeiling() {
        let quiet = InterviewAudioPolicy.limitedSample(0.02, linearGain: 2)
        let peak = InterviewAudioPolicy.limitedSample(1, linearGain: 3)

        #expect(quiet > 0.02)
        #expect(abs(peak) <= InterviewAudioPolicy.peakCeiling)
    }

    @Test func conditionalProcessorSkipsWhenModeIsOffOrAudioIsMissing() async throws {
        #expect(try await !InterviewAudioProcessor.processIfNeeded(at: nil, shouldProcess: true))
        #expect(try await !InterviewAudioProcessor.processIfNeeded(
            at: URL(fileURLWithPath: "/does/not/exist.m4a"),
            shouldProcess: false
        ))
    }

    @Test func processingBoostsAQuietM4AAndLeavesItReadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("quiet.m4a")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/quiet-interview-source.m4a")
        try FileManager.default.copyItem(at: fixtureURL, to: url)

        let result = try InterviewAudioProcessor.processSynchronouslyInPlace(at: url)
        let processed = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let processedBuffer = AVAudioPCMBuffer(
            pcmFormat: processed.processingFormat,
            frameCapacity: AVAudioFrameCount(processed.length)
        ) else {
            Issue.record("Could not allocate the processed audio buffer")
            return
        }
        try processed.read(into: processedBuffer)
        guard let processedSamples = processedBuffer.floatChannelData?[0] else {
            Issue.record("Processed audio was not non-interleaved Float32")
            return
        }
        var processedPeak: Float = 0
        for frame in 0..<Int(processedBuffer.frameLength) {
            processedPeak = max(processedPeak, abs(processedSamples[frame]))
        }

        #expect(result.appliedGainDecibels == InterviewAudioPolicy.maximumGainDecibels)
        #expect(processed.length > 0)
        #expect(processedPeak > 0.002)
        #expect(processedPeak <= InterviewAudioPolicy.peakCeiling + 0.01)
    }

    @Test func synchronousProcessingRejectsAMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).m4a")
        #expect(throws: InterviewAudioProcessingError.self) {
            try InterviewAudioProcessor.processSynchronouslyInPlace(at: url)
        }
    }

    @Test func asynchronousProcessingRejectsAMissingFile() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-async-\(UUID().uuidString).m4a")
        do {
            _ = try await InterviewAudioProcessor.processInPlace(at: url)
            Issue.record("A missing recording should fail processing")
        } catch is InterviewAudioProcessingError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
