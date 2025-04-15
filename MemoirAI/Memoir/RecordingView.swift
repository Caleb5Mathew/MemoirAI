import SwiftUI
import AVFoundation

struct RecordingView: View {
    let prompt: MemoryPrompt
    let chapterTitle: String
    var namespace: Namespace.ID

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel = MemoryEntryViewModel()

    @State private var typedText: String = ""
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioURL: URL?
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var showExitConfirm = false
    @State private var showSaveToast = false
    @State private var powerLevel: Float = 0.0
    @State private var timer: Timer?

    let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    let overlayBlack = Color.black.opacity(0.4)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(chapterTitle.lowercased())
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                overlayBlack.ignoresSafeArea()

                VStack(spacing: 32) {
                    // Prompt Bubble
                    Text(prompt.text)
                        .matchedGeometryEffect(id: prompt.id, in: namespace)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(terracotta)
                        .clipShape(Capsule())
                        .padding(.top, 60)

                    // Pulsing Dots from Audio Levels
                    HStack(spacing: 12) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(terracotta)
                                .frame(width: 12 + CGFloat(i * 2), height: 12 + CGFloat(i * 2))
                                .scaleEffect(CGFloat(1 + (powerLevel * Float(i + 1))))
                                .animation(.easeInOut(duration: 0.2), value: powerLevel)
                        }
                    }

                    // Control Buttons
                    HStack(spacing: 40) {
                        Button(action: clearRecording) {
                            controlIcon("gobackward")
                        }

                        Button(action: {
                            isPaused ? resumeRecording() : pauseRecording()
                        }) {
                            controlIcon(isPaused ? "play.fill" : "pause.fill")
                        }

                        Button(action: {
                            stopRecording()
                            saveMemory()
                        }) {
                            controlIcon("square.and.arrow.down")
                        }
                    }

                    Spacer()

                    // Text Field
                    HStack(spacing: 12) {
                        Image(systemName: "pencil")
                            .foregroundColor(.gray)
                        TextField("Type your answer...", text: $typedText)
                            .font(.system(size: 14))
                    }
                    .padding()
                    .background(softCream)
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Back Button
                VStack {
                    HStack {
                        Button(action: {
                            if hasUnsavedData() {
                                showExitConfirm = true
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.25))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)

                // Saved Toast
                if showSaveToast {
                    VStack {
                        Spacer()
                        Text("Memory Saved!")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .padding(.bottom, 60)
                            .transition(.opacity)
                    }
                }
            }
            .confirmationDialog("Exit without saving?", isPresented: $showExitConfirm) {
                Button("Discard and Exit", role: .destructive) {
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: setupRecorder)
            .onDisappear(perform: cleanup)
        }
    }

    func controlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .padding(20)
            .background(terracotta)
            .clipShape(Circle())
    }

    func setupRecorder() {
        let filename = UUID().uuidString + ".m4a"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: path, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            audioURL = path
            isRecording = true
            startMonitoringLevels()
        } catch {
            print("⚠️ Error starting recorder: \(error.localizedDescription)")
        }
    }

    func startMonitoringLevels() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard let recorder = audioRecorder else { return }
            recorder.updateMeters()
            powerLevel = max(0.05, min(1.0, pow(10, recorder.averagePower(forChannel: 0) / 20)))
        }
    }

    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        isRecording = false
    }

    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        isRecording = true
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        timer?.invalidate()
    }

    func clearRecording() {
        stopRecording()
        audioURL = nil
        typedText = ""
    }

    func saveMemory() {
        viewModel.addEntry(prompt: prompt.text, text: typedText.isEmpty ? nil : typedText, audioURL: audioURL)
        withAnimation {
            showSaveToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSaveToast = false
                dismiss()
            }
        }
    }

    func hasUnsavedData() -> Bool {
        return !typedText.isEmpty || audioURL != nil
    }

    func cleanup() {
        timer?.invalidate()
    }
}
