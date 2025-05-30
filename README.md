# MemoirAI - Life Storytelling App

A beautiful iOS app that helps users create and share their life stories through voice recordings, AI-powered transcription, and family sharing features.

## 🚀 Features

- **Voice Recording** - Capture memories with high-quality audio recording
- **Real-time Waveform Visualization** - Visual feedback during recording with voice activity detection
- **AI Transcription** - Convert voice recordings to text
- **Story Generation** - AI-powered story enhancement and formatting
- **Photo Integration** - Add photos to memories
- **Family Sharing** - Share stories with family members (in development)
- **Beautiful UI** - Warm, cream-colored design with thoughtful UX

## 🛠 Setup Instructions

### Prerequisites
- Xcode 15.0+
- iOS 16.0+
- Swift 5.9+

### API Key Configuration

1. **OpenAI API Key** (Required for AI features):
   - Add `OPENAI_API_KEY` to your `Info.plist`
   - Get your key from [OpenAI Platform](https://platform.openai.com/api-keys)

2. **RevenueCat API Key** (Optional for subscriptions):
   - Add `REVENUECAT_API_KEY` to your `Info.plist`
   - Get your key from [RevenueCat Dashboard](https://app.revenuecat.com/)

### Info.plist Example
```xml
<key>OPENAI_API_KEY</key>
<string>sk-your-actual-openai-api-key-here</string>
<key>REVENUECAT_API_KEY</key>
<string>your-revenuecat-api-key-here</string>
```

### Installation

1. Clone the repository
2. Open `MemoirAI.xcodeproj` in Xcode
3. Add your API keys to `Info.plist`
4. Build and run the project

## 📱 App Structure

- **Home** - Daily memory prompts and quick recording access
- **Saved Stories** - View all recorded memories and stories
- **Family** - Share stories with family members (coming soon)

## 🏗 Architecture

- **SwiftUI** - Modern declarative UI framework
- **Core Data** - Local data persistence
- **AVFoundation** - Audio recording and playback
- **Combine** - Reactive programming for data flow

## 📦 Key Components

- `RecordMemoryView` - Main recording interface with waveform visualization
- `FamilyManager` - Backend logic for family sharing features
- `MemoryEntry` - Core Data model for stored memories
- `AudioLevelMonitor` - Real-time audio level monitoring

## 🔒 Privacy & Security

- All voice recordings are stored locally
- API keys are configured through Info.plist (not committed to repo)
- User data is never shared without explicit permission

## 🚧 Development Status

- ✅ Core recording and playback functionality
- ✅ Real-time waveform visualization
- ✅ AI transcription and story generation
- 🚧 Family sharing features (in development)
- 🚧 Cloud sync capabilities

## 📝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

[Add your license information here]

## 📞 Support

[Add support contact information here] 