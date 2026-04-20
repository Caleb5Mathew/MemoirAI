# Memory Storage - Simple Visual Guide

## 🎯 What Happens When You Delete & Reinstall?

```
╔═══════════════════════════════════════════════════════════════════╗
║                    YOUR MEMORIES                                  ║
║                                                                   ║
║  ✅ SAFE - Will Come Back                                         ║
║  ┌─────────────────────────────────────────────────────────────┐ ║
║  │  • All memory text/transcripts                              │ ║
║  │  • All photos                                               │ ║
║  │  • All prompts                                             │ ║
║  │  • All metadata (dates, chapters)                          │ ║
║  │  • Audio recordings (backed up as data)                     │ ║
║  │  • Profile information                                      │ ║
║  │  • Settings & preferences                                   │ ║
║  └─────────────────────────────────────────────────────────────┘ ║
║                                                                   ║
║  ⚠️  NEEDS REGENERATION                                          ║
║  ┌─────────────────────────────────────────────────────────────┐ ║
║  │  • Generated storybooks (can recreate from memories)       │ ║
║  │  • Downloaded PDFs (can regenerate)                        │ ║
║  └─────────────────────────────────────────────────────────────┘ ║
╚═══════════════════════════════════════════════════════════════════╝
```

## 📊 Where Everything Lives

```
┌─────────────────────────────────────────────────────────┐
│  IN THE CLOUD (iCloud)                                  │
│  ─────────────────────────────────────────────────────  │
│                                                         │
│  📦 CloudKit                                            │
│     └─ Your memories, photos, audio data               │
│                                                         │
│  📋 iCloud Key-Value Store                              │
│     └─ Your profiles, settings                         │
│                                                         │
│  ✅ These survive deletion & sync across devices        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  ON YOUR DEVICE (Local)                                 │
│  ─────────────────────────────────────────────────────  │
│                                                         │
│  📁 Documents Folder                                    │
│     └─ Audio files, PDFs, profile JSON                 │
│                                                         │
│  ⚙️  App Settings                                       │
│     └─ Storybook data, preferences                     │
│                                                         │
│  ⚠️  These are lost on deletion                         │
│  ✅ But important stuff is backed up to cloud           │
└─────────────────────────────────────────────────────────┘
```

## 🔄 Simple Flow

```
You Record Memory
        │
        ├─► Saved to CloudKit ──────► ✅ Safe forever
        │
        ├─► Saved to Device ─────────► ⚠️  Lost if app deleted
        │                              (but cloud backup exists)
        │
        └─► Synced to iCloud ────────► ✅ Available on all devices
```

## ✅ Bottom Line

**Your memories are SAFE!**

- ✅ All your memory entries persist via iCloud
- ✅ All your photos persist via iCloud  
- ✅ All your profiles persist via iCloud
- ✅ Audio recordings are backed up (can recreate files)
- ⚠️  Only generated content (storybooks/PDFs) needs regeneration

**When you delete & reinstall:**
- Your memories come back ✅
- Your photos come back ✅
- Your profiles come back ✅
- Generated storybooks need to be recreated ⚠️










