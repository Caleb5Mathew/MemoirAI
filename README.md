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

OpenAI (and optional Gemini) keys are **not** committed in `Info.plist` in many setups. The app resolves keys in this order:

1. **Run scheme environment variables** (good for local dev): Xcode → **Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables** — add `OPENAI_API_KEY` = `sk-…` (and `GEMINI_API_KEY` if you use image generation).
2. **`MemoirAI/secrets.plist`** (gitignored): copy `MemoirAI/secrets.example.plist` to `MemoirAI/secrets.plist`, paste your keys into the string values, then build. The file is excluded from git but picked up by the app target.
3. **`Info.plist`**: set `OPENAI_API_KEY` / `GEMINI_API_KEY` string values (avoid committing real keys to a public repo).

Implementation: see `AppAPIKeys.swift`.

Get an OpenAI key from [OpenAI Platform](https://platform.openai.com/api-keys).

2. **RevenueCat API Key** (Optional for subscriptions):
   - Add `REVENUECAT_API_KEY` to your `Info.plist`
   - Get your key from [RevenueCat Dashboard](https://app.revenuecat.com/)

### Info.plist Example (if you use Info.plist for keys)
```xml
<key>OPENAI_API_KEY</key>
<string>sk-your-actual-openai-api-key-here</string>
<key>REVENUECAT_API_KEY</key>
<string>your-revenuecat-api-key-here</string>
```

### Installation

1. Clone the repository
2. Open `MemoirAI.xcodeproj` in Xcode
3. Add your API keys using one of the options above (scheme, `secrets.plist`, or `Info.plist`)
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

### Firebase Cloud Functions (`functions/`)

- Style paragraphs for Gemini live in **`functions/style/bookStyles.json`** (server-side generation). After edits, run:

  `cd functions && npm run check-style-sync`

- Admin/support callable **`adminListUserBooks`** lists another user’s `bookVersions` when the caller is allow-listed via env **`ADMIN_EMAILS`** (comma-separated) or Auth custom claim **`admin: true`**.
- **Print fulfillment ops:** paid orders wait for manual **Print** by default. Web queue: deploy hosting, open `/ops`, sign in as admin. See **[`OPS_PRINT_QUEUE.md`](OPS_PRINT_QUEUE.md)** (`ADMIN_EMAILS`, `AUTO_FULFILL_PAID_ORDERS`, `adminListPrintOrders`, `fulfillOrder`).
- **`artStyle`** on `storybookJobs` / `bookVersions` should use canonical keys (`kidsBook`, `realistic`, `comic`, `custom`). The worker normalizes legacy iOS display strings (e.g. `Kid's Book`) so old jobs still render correctly.

### Storybook pipeline QA (manual)

After changing prompts or job routing, re-run cloud generation on a small set of memories (e.g. child-age narrator + headshot, multi-person sparse cards, mixed-heritage family) and confirm: narrator age matches cards, no ethnicity bleed to unnamed relatives, no duplicate headshot faces on extras, and a new queued job dismisses older `failed` rows from the progress banner.

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