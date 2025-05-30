import SwiftUI

struct RealTimeWaveformView: View {
    @ObservedObject var audioMonitor: AudioLevelMonitor
    let isRecording: Bool
    let isPaused: Bool
    
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 2
    private let maxBarHeight: CGFloat = 40
    
    // Colors matching app theme
    private let activeColor = Color(red: 0.88, green: 0.52, blue: 0.28) // Orange mic color
    private let voiceActiveColor = Color(red: 0.10, green: 0.22, blue: 0.14) // Accent green
    private let silentColor = Color.gray.opacity(0.3)
    
    var body: some View {
        VStack(spacing: 16) {
            // Voice Activity Indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(audioMonitor.isVoiceActive ? voiceActiveColor : silentColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(audioMonitor.isVoiceActive ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: audioMonitor.isVoiceActive)
                
                Text(audioMonitor.isVoiceActive ? "Speaking" : "Listening...")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(audioMonitor.isVoiceActive ? voiceActiveColor : silentColor)
                    .animation(.easeInOut(duration: 0.3), value: audioMonitor.isVoiceActive)
            }
            .opacity((isRecording && !isPaused) ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.3), value: isRecording && !isPaused)
            
            // Waveform Visualization
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<audioMonitor.waveformLevels.count, id: \.self) { index in
                    WaveformBar(
                        level: audioMonitor.waveformLevels[index],
                        isActive: isRecording && !isPaused,
                        isVoiceActive: audioMonitor.isVoiceActive,
                        index: index,
                        totalBars: audioMonitor.waveformLevels.count
                    )
                }
            }
            .frame(height: maxBarHeight)
            .opacity((isRecording || isPaused) ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.5), value: isRecording || isPaused)
            
            // Audio Level Indicator (circular progress around mic button)
            if isRecording && !isPaused {
                VStack(spacing: 4) {
                    Text("Level")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    CircularAudioLevelView(level: audioMonitor.getSmoothedLevel())
                        .frame(width: 60, height: 60)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isRecording)
    }
}

struct WaveformBar: View {
    let level: Double
    let isActive: Bool
    let isVoiceActive: Bool
    let index: Int
    let totalBars: Int
    
    private let barWidth: CGFloat = 3
    private let minBarHeight: CGFloat = 2
    private let maxBarHeight: CGFloat = 40
    
    private var barHeight: CGFloat {
        let normalizedHeight = CGFloat(level) * (maxBarHeight - minBarHeight) + minBarHeight
        return max(minBarHeight, normalizedHeight)
    }
    
    private var barColor: Color {
        if !isActive {
            return Color.gray.opacity(0.2)
        }
        
        // Recent bars (right side) get more vibrant colors
        let recentnessFactor = Double(index) / Double(totalBars)
        let opacity = 0.3 + (recentnessFactor * 0.7)
        
        if isVoiceActive {
            return Color(red: 0.10, green: 0.22, blue: 0.14).opacity(opacity)
        } else {
            return Color(red: 0.88, green: 0.52, blue: 0.28).opacity(opacity)
        }
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(barColor)
            .frame(width: barWidth, height: barHeight)
            .animation(.easeOut(duration: 0.1), value: barHeight)
            .animation(.easeInOut(duration: 0.3), value: barColor)
    }
}

struct CircularAudioLevelView: View {
    let level: Double
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
            
            // Level indicator
            Circle()
                .trim(from: 0, to: CGFloat(level))
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.52, blue: 0.28),
                            Color(red: 0.10, green: 0.22, blue: 0.14)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.1), value: level)
            
            // Center dot
            Circle()
                .fill(level > 0.1 ? Color(red: 0.10, green: 0.22, blue: 0.14) : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
                .scaleEffect(level > 0.5 ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: level)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        // Preview with mock data
        RealTimeWaveformView(
            audioMonitor: {
                let monitor = AudioLevelMonitor()
                // Set some mock data for preview
                monitor.waveformLevels = (0..<50).map { i in
                    sin(Double(i) * 0.3) * 0.5 + 0.5
                }
                monitor.isVoiceActive = true
                return monitor
            }(),
            isRecording: true,
            isPaused: false
        )
        .padding()
        
        CircularAudioLevelView(level: 0.7)
            .frame(width: 60, height: 60)
    }
    .background(Color(red: 1.0, green: 0.96, blue: 0.89))
} 