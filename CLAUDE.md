# MemoirAI

iOS SwiftUI memoir creation app. Firebase (Auth, Firestore, Storage, Functions), RevenueCat, Stripe, Mixpanel. iOS 16+ minimum.

## Build & Test

- **Build**: Use `BuildProject` MCP tool (Xcode must be open with this project)
- **Tests**: Use `RunAllTests` or `RunSomeTests` — targets: MemoirAITests, MemoirAIUITests
- **Xcode issues**: `XcodeListNavigatorIssues` to see build errors and warnings
- **Functions syntax check**: `cd functions && node -e "require('./index')" 2>&1`
- **Never** use `xcodebuild` from the shell when Xcode MCP tools are available

## Architecture

```
MemoirAI/
  Auth/              — Sign in, Google/Facebook, session management
  Memoir/            — Core memoir flow, chapter journey, recording UI
  Memory/            — Memory entry, audio playback, Core Data persistence
  Story/             — Story generation, flipbook rendering (WKWebView bridge)
  MemoirPreview/     — Book preview, PDF download, page rendering
  Firebase/          — Service wrappers ONLY: AuthService, FirestoreSyncService, StorageService, OrderService
  Models/            — Pure Swift data models, no UI dependencies
  GrandparentProfile/— Profile management for the memoir subject
  Home/              — Tab bar, homepage, prompt of the day
functions/           — Firebase Cloud Functions (Node.js): PDF gen (pdf-lib), AI image, Stripe
```

## Key Rules

- **Views never call Firebase directly** — always go through a service in `Firebase/`
- **AI image generation goes through `functions/index.js`** — not the iOS client
- **Firestore writes use FirestoreSyncService** — not raw `db.collection()` calls
- **RevenueCat is the source of truth for subscription state** — never roll custom paywall logic
- **PDF generation lives in `functions/`** using pdf-lib — not on-device

## Key Files

- `MemoirAI/NavigationRouter.swift` — App-wide navigation state; changes ripple everywhere
- `MemoirAI/Firebase/FirestoreSyncService.swift` — All Firestore read/write operations
- `MemoirAI/Models/CharacterDetails.swift` — Core data model; changes affect the whole app
- `MemoirAI/Memoir/RecordingView.swift` — Audio recording; most complex view in the app
- `functions/index.js` — All Cloud Functions (~1500 lines); PDF, AI, Stripe, auth triggers

## Gotchas

- **iCloud sync** (`Memory/iCloudManager.swift`) is partially implemented — read it fully before touching it
- **FlipbookView** uses WKWebView with a JS bridge — changes to `flipbook.css` or JS require testing the web view separately, not just SwiftUI previews
- **Stripe keys**: `scripts/swap-to-live-stripe.sh` exists for prod key swap — never hardcode live keys
- **`output/` directory** contains debug artifacts — never commit anything in `output/`
- **Worktrees**: This project uses git worktrees; branches under `MemoirAI/.claude/worktrees/` are active
