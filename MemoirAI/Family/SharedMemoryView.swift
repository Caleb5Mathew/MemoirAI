import SwiftUI
import AVFoundation

/// Read-only remote memory playback for granted family and friends. Deliberately not
/// MemoryDetailView (which is bound to a local Core Data entry and its editing UI) —
/// this streams straight from the memory's Firestore doc and audio URL.
struct SharedMemoryView: View {
    let route: SharedMemoryRoute

    @State private var memory: SharedAccessService.RemoteMemory? = nil
    @State private var loadFailed = false
    @State private var player: AVPlayer? = nil
    @State private var localAudioURL: URL? = nil
    @State private var isPlaying = false
    @State private var isLoadingAudio = false
    @State private var playbackTask: Task<Void, Never>? = nil
    @State private var isVisible = false
    @State private var playbackError: String? = nil

    private let darkText = Color(red: 0.25, green: 0.2, blue: 0.15)
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)

    var body: some View {
        Group {
            if let memory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let name = memory.profileName, !name.isEmpty {
                            Text("From \(name)'s memoir")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(darkText.opacity(0.6))
                        }

                        if let prompt = memory.prompt, !prompt.isEmpty {
                            Text(prompt)
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundColor(darkText)
                        }

                        if memory.audioStoragePath != nil {
                            Button {
                                togglePlayback()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundColor(terracotta)
                                    Text(isLoadingAudio ? "Loading audio…" : (isPlaying ? "Pause" : "Hear this memory"))
                                        .font(.system(size: 17, weight: .semibold, design: .serif))
                                        .foregroundColor(darkText)
                                    Spacer()
                                }
                                .padding(16)
                                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingAudio)
                        }

                        if let playbackError {
                            Text(playbackError)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }

                        if let transcription = memory.transcription, !transcription.isEmpty {
                            Text(transcription)
                                .font(.system(size: 17, design: .serif))
                                .foregroundColor(darkText.opacity(0.85))
                                .lineSpacing(6)
                        }
                    }
                    .padding(24)
                }
            } else if loadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(terracotta)
                    Text("Could not load this memory")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundColor(darkText)
                    Text("Check your connection and try again.")
                        .font(.system(size: 14))
                        .foregroundColor(darkText.opacity(0.6))
                }
            } else {
                ProgressView("Loading memory…")
            }
        }
        .task { await load() }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            playbackTask?.cancel()
            playbackTask = nil
            stopPlayback()
        }
    }

    private func load() async {
        do {
            memory = try await SharedAccessService.shared.fetchSharedMemory(
                ownerId: route.ownerId,
                memoryId: route.memoryId
            )
        } catch {
            print("[SharedMemory] load failed: \(error.localizedDescription)")
            loadFailed = true
        }
    }

    private func togglePlayback() {
        guard let storagePath = memory?.audioStoragePath else { return }
        Haptics.tap()
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        guard player == nil, !isLoadingAudio else { return }
        isLoadingAudio = true
        playbackTask = Task { @MainActor in
            defer {
                isLoadingAudio = false
                playbackTask = nil
            }
            do {
                let url = try await SharedAccessService.shared.downloadSharedAudio(
                    ownerId: route.ownerId,
                    memoryId: route.memoryId,
                    storagePath: storagePath
                )
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                guard isVisible else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                localAudioURL = url
                playbackError = nil
            } catch {
                if error is CancellationError { return }
                playbackError = "This audio is no longer shared or could not be downloaded."
                return
            }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("[SharedMemory] audio session error: \(error.localizedDescription)")
            }
            guard let localAudioURL, isVisible, !Task.isCancelled else { return }
            player = AVPlayer(url: localAudioURL)
            player?.play()
            isPlaying = true
        }
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        isPlaying = false
        if let localAudioURL {
            try? FileManager.default.removeItem(at: localAudioURL)
            self.localAudioURL = nil
        }
    }
}
