import AVFoundation
import Darwin
import Foundation

struct InterviewAudioProcessingResult: Equatable, Sendable {
    let appliedGainDecibels: Float
    let inputRMSDecibels: Float
}

enum InterviewAudioProcessingError: LocalizedError {
    case missingRecording
    case unsupportedAudioFormat
    case emptyRecording
    case analysisFailed(String)
    case encodingFailed(String)
    case validationFailed(String)
    case couldNotReplaceRecording(Int32)

    var errorDescription: String? {
        switch self {
        case .missingRecording:
            return "The recording file could not be found."
        case .unsupportedAudioFormat:
            return "The recording format could not be processed."
        case .emptyRecording:
            return "The recording did not contain any audio."
        case .analysisFailed(let message):
            return "The recording could not be analyzed: \(message)"
        case .encodingFailed(let message):
            return "The recording could not be encoded: \(message)"
        case .validationFailed(let message):
            return "The processed recording could not be validated: \(message)"
        case .couldNotReplaceRecording:
            return "The processed recording could not be saved."
        }
    }
}

enum InterviewAudioPolicy {
    static let targetRMSDecibels: Float = -20
    static let maximumGainDecibels: Float = 9
    static let peakCeiling: Float = 0.891_250_9
    static let compressionThreshold: Float = 0.501_187_2
    static let compressionRatio: Float = 4

    static func shouldProcess(isDeveloperUnlocked: Bool, isEnabledForProfile: Bool) -> Bool {
        isDeveloperUnlocked && isEnabledForProfile
    }

    static func gainDecibels(inputRMSDecibels: Float) -> Float {
        guard inputRMSDecibels.isFinite else { return 0 }
        return min(maximumGainDecibels, max(0, targetRMSDecibels - inputRMSDecibels))
    }

    static func limitedSample(_ sample: Float, linearGain: Float) -> Float {
        let amplified = sample * max(1, linearGain)
        let magnitude = abs(amplified)
        guard magnitude > compressionThreshold else { return amplified }
        let compressed = compressionThreshold
            + ((magnitude - compressionThreshold) / compressionRatio)
        return copysign(min(compressed, peakCeiling), amplified)
    }
}

enum InterviewAudioProcessor {
    private static let bufferFrameCount: AVAudioFrameCount = 16_384

    static func processIfNeeded(at url: URL?, shouldProcess: Bool) async throws -> Bool {
        guard shouldProcess, let url else { return false }
        _ = try await processInPlace(at: url)
        return true
    }

    static func processInPlace(at url: URL) async throws -> InterviewAudioProcessingResult {
        try await Task.detached(priority: .userInitiated) {
            try processSynchronouslyInPlace(at: url)
        }.value
    }

    static func processSynchronouslyInPlace(at url: URL) throws -> InterviewAudioProcessingResult {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw InterviewAudioProcessingError.missingRecording
        }

        let analysis: (rms: Float, sampleRate: Double, channelCount: AVAudioChannelCount)
        do {
            analysis = try autoreleasepool { () throws -> (rms: Float, sampleRate: Double, channelCount: AVAudioChannelCount) in
                let input = try AVAudioFile(
                    forReading: url,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                let format = input.processingFormat
                guard format.channelCount > 0, format.sampleRate > 0,
                      let analysisBuffer = AVAudioPCMBuffer(
                        pcmFormat: format,
                        frameCapacity: bufferFrameCount
                      ) else {
                    throw InterviewAudioProcessingError.unsupportedAudioFormat
                }

                var squareSum = 0.0
                var sampleCount = 0
                while input.framePosition < input.length {
                    analysisBuffer.frameLength = 0
                    let remainingFrames = AVAudioFrameCount(input.length - input.framePosition)
                    try input.read(
                        into: analysisBuffer,
                        frameCount: min(bufferFrameCount, remainingFrames)
                    )
                    guard analysisBuffer.frameLength > 0 else { break }
                    guard let channels = analysisBuffer.floatChannelData else {
                        throw InterviewAudioProcessingError.unsupportedAudioFormat
                    }
                    for channel in 0..<Int(format.channelCount) {
                        for frame in 0..<Int(analysisBuffer.frameLength) {
                            let sample = Double(channels[channel][frame])
                            squareSum += sample * sample
                            sampleCount += 1
                        }
                    }
                }
                guard sampleCount > 0 else { throw InterviewAudioProcessingError.emptyRecording }
                return (
                    rms: Float(sqrt(squareSum / Double(sampleCount))),
                    sampleRate: format.sampleRate,
                    channelCount: format.channelCount
                )
            }
        } catch let error as InterviewAudioProcessingError {
            throw error
        } catch {
            throw InterviewAudioProcessingError.analysisFailed(error.localizedDescription)
        }

        let inputRMSDecibels = analysis.rms > 0 ? 20 * log10(analysis.rms) : -160
        let gainDecibels = InterviewAudioPolicy.gainDecibels(inputRMSDecibels: inputRMSDecibels)
        let linearGain = pow(10, gainDecibels / 20)

        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)-interview-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: analysis.sampleRate,
            AVNumberOfChannelsKey: analysis.channelCount,
            AVEncoderBitRateKey: 48_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            try autoreleasepool {
                let input = try AVAudioFile(
                    forReading: url,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                let output = try AVAudioFile(
                    forWriting: temporaryURL,
                    settings: outputSettings,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                guard input.processingFormat == output.processingFormat,
                      let processingBuffer = AVAudioPCMBuffer(
                    pcmFormat: input.processingFormat,
                    frameCapacity: bufferFrameCount
                ) else {
                    throw InterviewAudioProcessingError.unsupportedAudioFormat
                }

                while input.framePosition < input.length {
                    processingBuffer.frameLength = 0
                    let remainingFrames = AVAudioFrameCount(input.length - input.framePosition)
                    try input.read(
                        into: processingBuffer,
                        frameCount: min(bufferFrameCount, remainingFrames)
                    )
                    guard processingBuffer.frameLength > 0 else { break }
                    guard let channels = processingBuffer.floatChannelData else {
                        throw InterviewAudioProcessingError.unsupportedAudioFormat
                    }
                    for channel in 0..<Int(processingBuffer.format.channelCount) {
                        for frame in 0..<Int(processingBuffer.frameLength) {
                            channels[channel][frame] = InterviewAudioPolicy.limitedSample(
                                channels[channel][frame],
                                linearGain: linearGain
                            )
                        }
                    }
                    try output.write(from: processingBuffer)
                }
            }
        } catch let error as InterviewAudioProcessingError {
            throw error
        } catch {
            throw InterviewAudioProcessingError.encodingFailed(error.localizedDescription)
        }

        let validationFile: AVAudioFile
        do {
            validationFile = try AVAudioFile(forReading: temporaryURL)
        } catch {
            throw InterviewAudioProcessingError.validationFailed(error.localizedDescription)
        }
        guard validationFile.length > 0 else { throw InterviewAudioProcessingError.emptyRecording }
        let renameResult = temporaryURL.path.withCString { source in
            url.path.withCString { destination in
                Darwin.rename(source, destination)
            }
        }
        guard renameResult == 0 else {
            throw InterviewAudioProcessingError.couldNotReplaceRecording(errno)
        }
        return InterviewAudioProcessingResult(
            appliedGainDecibels: gainDecibels,
            inputRMSDecibels: inputRMSDecibels
        )
    }
}
