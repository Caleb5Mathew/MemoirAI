# MemoirAI — Agent Context

## Project Overview

MemoirAI is an iOS SwiftUI app for life storytelling and memoir creation. Uses Firebase (Auth, Firestore, Storage, Functions), RevenueCat, Mixpanel, and has unit/UI tests.

## Build System

- **Xcode project:** `MemoirAI.xcodeproj`
- Use `BuildProject` to compile — do not use shell commands like `xcodebuild` when Xcode tools are available
- SwiftUI previews available via `RenderPreview`

## Testing

- Run tests with `RunAllTests` or `RunSomeTests`
- Test targets: MemoirAITests, MemoirAIUITests
- Test results available via Xcode's test navigator (`XcodeListNavigatorIssues`)

## Stripe (print orders / hosted Checkout)

- Production checklist: [`STRIPE_GO_LIVE_CHECKLIST.md`](STRIPE_GO_LIVE_CHECKLIST.md)
- Local sanity script (no API calls): `./scripts/stripe-readiness-gates.sh`
- Live secret setup: `./scripts/swap-to-live-stripe.sh` — requires `STRIPE_LIVE_SECRET_KEY` or interactive paste (never commit keys)

## Documentation

- Use `DocumentationSearch` to find Apple API docs and WWDC session transcripts
- Semantic search covers iOS 15–26 documentation

## Xcode MCP Tools

When helping with this project, use Xcode tools (via `xcode-tools` MCP server) when appropriate:

- **BuildProject** — Build the app
- **RunAllTests** / **RunSomeTests** — Run tests
- **GetBuildLog** — Get build output
- **DocumentationSearch** — Search Apple docs
- **RenderPreview** — Render SwiftUI previews as images
- **XcodeRead** / **XcodeWrite** / **XcodeUpdate** — Read/write project files
- **XcodeGrep** / **XcodeGlob** — Search and find files

**Note:** Xcode must be running with this project open for these tools to work.
