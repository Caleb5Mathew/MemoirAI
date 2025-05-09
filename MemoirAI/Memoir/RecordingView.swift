import SwiftUI
import AVFoundation
import CoreData

struct RecordingView: View {
    let prompt: MemoryPrompt
    let chapterTitle: String
    var namespace: Namespace.ID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel

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
                    Spacer(minLength: geo.size.height * 0.12)

                    VStack(spacing: 24) {
                        Text(prompt.text)
                            .matchedGeometryEffect(id: prompt.id, in: namespace)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(terracotta)
                            .clipShape(Capsule())

                        HStack(spacing: 12) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(terracotta)
                                    .frame(width: 12 + CGFloat(i * 2), height: 12 + CGFloat(i * 2))
                                    .scaleEffect(CGFloat(1 + (powerLevel * Float(i + 1))))
                                    .animation(.easeInOut(duration: 0.2), value: powerLevel)
                            }
                        }

                        HStack(spacing: 40) {
                            controlButton(icon: "gobackward", label: "Restart") { clearRecording() }
                            controlButton(icon: isPaused ? "play.fill" : "pause.fill", label: isPaused ? "Resume" : "Pause") {
                                isPaused ? resumeRecording() : pauseRecording()
                            }
                            controlButton(icon: "square.and.arrow.down", label: "Save") {
                                stopRecording()
                                saveMemory()
                            }
                        }
                    }
                    .frame(maxWidth: geo.size.width * 0.9)
                    .multilineTextAlignment(.center)

                    Text("Or")
                        .foregroundColor(.white)
                        .font(.caption)

                    ZStack(alignment: .topLeading) {
                        if typedText.isEmpty {
                            Text("Type your answer...")
                                .foregroundColor(.gray)
                                .padding(.top, 12)
                                .padding(.leading, 36)
                        }

                        TextEditor(text: $typedText)
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                            .frame(minHeight: 60, maxHeight: 120)
                            .padding(.top, 8)
                            .padding(.leading, 32)
                            .scrollContentBackground(.hidden)
                            .background(softCream)

                        Image(systemName: "pencil")
                            .foregroundColor(.gray)
                            .padding(.top, 14)
                            .padding(.leading, 10)
                    }
                    .background(softCream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, geo.size.width * 0.08)

                    Spacer()
                }
                .frame(maxWidth: geo.size.width)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

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
                    .frame(maxWidth: .infinity)
                }
            }
            .confirmationDialog("Exit without saving?", isPresented: $showExitConfirm) {
                Button("Discard and Exit", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: setupRecorder)
            .onDisappear(perform: cleanup)
        }
    }

    func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(20)
                    .background(terracotta)
                    .clipShape(Circle())
            }
            Text(label)
                .foregroundColor(.white)
                .font(.caption)
        }
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
            let level = max(0.05, min(1.0, pow(10, recorder.averagePower(forChannel: 0) / 20)))
            powerLevel = level
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
        let profileID = profileVM.selectedProfile.id
        print("📝 Saving Memory for Profile ID: \(profileID)")
        print("📝 Prompt: \(prompt.text)")
        print("📝 Chapter: \(chapterTitle)")
        print("📝 Typed Text: \(typedText.isEmpty ? "None" : typedText)")
        print("📝 Audio URL: \(audioURL?.absoluteString ?? "None")")

        let newEntry = MemoryEntry(context: context)
        newEntry.id = UUID()
        newEntry.prompt = prompt.text
        newEntry.text = typedText.isEmpty ? nil : typedText
        newEntry.audioFileURL = audioURL?.absoluteString
        newEntry.createdAt = Date()
        newEntry.chapter = chapterTitle
        newEntry.profileID = profileID

        do {
            try context.save()
            NotificationCenter.default.post(name: .memorySaved, object: nil)
            print("✅ Memory Saved Successfully.")
            withAnimation {
                showSaveToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation {
                    showSaveToast = false
                    dismiss()
                }
            }
        } catch {
            print("❌ Error saving Memory: \(error)")
        }
    }

    func hasUnsavedData() -> Bool {
        return !typedText.isEmpty || audioURL != nil
    }

    func cleanup() {
        timer?.invalidate()
    }
}
