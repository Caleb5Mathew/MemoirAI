# QR Code Deep Linking - Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    QR CODE GENERATION (Storybook)                   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │  StoryPageViewModel.swift │
                    │  Line 1810                │
                    └───────────────────────────┘
                                    │
                    Creates: memoirai://memory/{UUID}
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   EnhancedQRCodePage      │
                    │   (StoryPage.swift)       │
                    │   Renders QR visual       │
                    └───────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   PDF Export / Display    │
                    │   QR code scannable       │
                    └───────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    USER SCANS QR CODE WITH CAMERA                   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   iOS Camera App          │
                    │   Recognizes memoirai://  │
                    └───────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   iOS System Prompt       │
                    │   "Open in MemoirAI?"     │
                    └───────────────────────────┘
                                    │
                        User taps "Open"
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   MemoirAI App Launches   │
                    │   or Foregrounds          │
                    └───────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    DEEP LINK HANDLING (In App)                      │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   ContentView.swift       │
                    │   .onOpenURL { url in }   │
                    │   Line 46                 │
                    └───────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   handleDeepLink(url)     │
                    │   Validates URL format    │
                    └───────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
            Valid Format?                   Invalid Format
                    │                               │
                    ▼                               ▼
        ┌───────────────────────┐      ┌──────────────────────┐
        │  Extract UUID         │      │  Show Error Alert    │
        │  from path            │      │  "Invalid format"    │
        └───────────────────────┘      └──────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  Check if onboarding  │
        │  is complete          │
        └───────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
  Onboarding Done        Onboarding Pending
        │                       │
        ▼                       ▼
┌──────────────────┐   ┌──────────────────────┐
│ Verify memory    │   │ Queue deep link      │
│ exists in DB     │   │ Show setup message   │
└──────────────────┘   └──────────────────────┘
        │
┌───────┴───────┐
│               │
Found       Not Found
│               │
▼               ▼
┌──────────────────┐   ┌──────────────────────┐
│ Call Navigation  │   │ Show Error Alert     │
│ Router           │   │ "Memory not found"   │
└──────────────────┘   └──────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    NAVIGATION & DISPLAY                             │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   NavigationRouter.swift  │
                    │   showMemoryDetail(id:)   │
                    │   Line 23                 │
                    └───────────────────────────┘
                                    │
                    Sets: selectedMemoryID = UUID
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   ContentView.swift       │
                    │   .onReceive(nav.$...)    │
                    │   Line 20                 │
                    └───────────────────────────┘
                                    │
                    Appends UUID to NavigationPath
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   NavigationStack         │
                    │   .navigationDestination  │
                    │   Line 26                 │
                    └───────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   Persistence.swift       │
                    │   entry(id: UUID)         │
                    │   Line 83                 │
                    └───────────────────────────┘
                                    │
                    Fetches MemoryEntry from Core Data
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   MemoryDetailView.swift  │
                    │   Displays memory         │
                    │   Line 112                │
                    └───────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    AUDIO PLAYBACK                                   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   MemoryDetailView        │
                    │   Shows play button       │
                    │   Line 168                │
                    └───────────────────────────┘
                                    │
                        User taps play button
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   togglePlayback(url:)    │
                    │   Line 542                │
                    └───────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   MemoryEntry+Playback    │
                    │   playbackURL property    │
                    └───────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
            Has audioFileURL              Has audioData
                    │                               │
                    ▼                               ▼
        ┌───────────────────────┐      ┌──────────────────────┐
        │  Return file URL      │      │  Write to temp file  │
        │  if exists            │      │  Return temp URL     │
        └───────────────────────┘      └──────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   AVAudioEngine           │
                    │   Plays audio with        │
                    │   +22dB EQ boost          │
                    └───────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────┐
                    │   🔊 Audio plays through  │
                    │      device speaker       │
                    └───────────────────────────┘

═══════════════════════════════════════════════════════════════════════

                        ✅ COMPLETE FLOW ✅

    QR Code → Camera → iOS → App → Parse → Validate → Navigate → Play

═══════════════════════════════════════════════════════════════════════
```

## Key Components Summary

| Component | File | Purpose | Status |
|-----------|------|---------|--------|
| QR Generation | StoryPageViewModel.swift | Creates `memoirai://memory/{UUID}` | ✅ |
| QR Display | StoryPage.swift | Renders QR code page | ✅ |
| URL Scheme | Info.plist | Registers `memoirai://` | ✅ |
| Deep Link Handler | ContentView.swift | Catches & parses URLs | ✅ |
| Navigation Router | NavigationRouter.swift | Routes to memory | ✅ |
| Memory Lookup | Persistence.swift | Fetches from Core Data | ✅ |
| Detail View | MemoryDetailView.swift | Shows memory + audio | ✅ |
| Audio Playback | MemoryEntry+Playback.swift | Provides audio URL | ✅ |

## Error Handling at Each Stage

1. **Invalid URL format** → User alert
2. **Invalid UUID** → User alert
3. **Memory not found** → User alert
4. **Onboarding incomplete** → Queue link, show message
5. **No audio available** → Hide play button gracefully
6. **Audio file missing** → Fallback to data blob

## Debug Logging

Every critical step logs to console with emoji prefixes:
- 🔗 Deep linking events
- ✅ Success operations
- ❌ Error conditions
- ⏳ Pending/queued operations

**Result: 100% Complete & Production Ready** 🎉


