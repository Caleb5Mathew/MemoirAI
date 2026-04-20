# Memory Storage - Quick Reference Diagram

## 🎯 What Survives App Deletion/Reinstall?

```
┌────────────────────────────────────────────────────────────────────────┐
│                         ✅ SURVIVES (via iCloud)                       │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────┐     │
│  │  CLOUDKIT (Core Data)                                        │     │
│  │  Container: iCloud.com.Buildr.MemoirAI                      │     │
│  ├──────────────────────────────────────────────────────────────┤     │
│  │                                                              │     │
│  │  ✅ Memory Entries                                          │     │
│  │     ├─ Text/Transcripts                                     │     │
│  │     ├─ Prompts                                              │     │
│  │     ├─ Metadata (dates, chapters)                          │     │
│  │     ├─ Audio Data (binary backup)                           │     │
│  │     └─ Photos (image data)                                  │     │
│  │                                                              │     │
│  │  ✅ Relationships                                            │     │
│  │     └─ MemoryEntry ↔ Photo                                  │     │
│  │                                                              │     │
│  └──────────────────────────────────────────────────────────────┘     │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────┐     │
│  │  ICLOUD KEY-VALUE STORE                                      │     │
│  ├──────────────────────────────────────────────────────────────┤     │
│  │                                                              │     │
│  │  ✅ Profile Data                                             │     │
│  │     ├─ Names, photos                                        │     │
│  │     ├─ Birthdates, ethnicity, gender                        │     │
│  │     └─ Selected profile index                               │     │
│  │                                                              │     │
│  │  ✅ Settings                                                 │     │
│  │     ├─ Storybook preferences                                │     │
│  │     ├─ Art style, page count                                │     │
│  │     └─ Onboarding state                                     │     │
│  │                                                              │     │
│  └──────────────────────────────────────────────────────────────┘     │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│                    ⚠️  RECOVERABLE (from backups)                       │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  🔄 Audio Files                                                        │
│     ├─ Local files: ❌ Lost (paths invalid)                           │
│     └─ Binary backup: ✅ Exists in Core Data                          │
│     └─ Action: Can recreate files from binary                         │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│                         ❌ LOST (not backed up)                         │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  ❌ Generated Storybook JSON                                           │
│     └─ Stored in UserDefaults (not synced)                           │
│     └─ Action: Can regenerate from memory entries                     │
│                                                                        │
│  ❌ Generated PDF Files                                               │
│     └─ Stored in Documents directory                                  │
│     └─ Action: Can regenerate from storybook                          │
│                                                                        │
│  ❌ Local UserDefaults (various flags)                                │
│     └─ Character details backup                                       │
│     └─ Various UI state flags                                         │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

## 📊 Storage Locations Map

```
┌─────────────────────────────────────────────────────────────────────┐
│                        STORAGE HIERARCHY                            │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  TIER 1: CLOUDKIT (iCloud.com.Buildr.MemoirAI)                     │
│  ────────────────────────────────────────────────────────────────── │
│  ✅ MemoryEntry entities                                             │
│  ✅ Photo entities                                                   │
│  ✅ All relationships                                                │
│  ✅ Audio binary data                                                │
│  └─ Syncs automatically, survives deletion                          │
└─────────────────────────────────────────────────────────────────────┘
         │
         │ (primary storage)
         │
┌────────▼────────────────────────────────────────────────────────────┐
│  TIER 2: ICLOUD KEY-VALUE STORE                                     │
│  ────────────────────────────────────────────────────────────────── │
│  ✅ Profile backups                                                  │
│  ✅ Settings & preferences                                           │
│  ✅ Onboarding state                                                 │
│  └─ Backup for critical user data                                   │
└─────────────────────────────────────────────────────────────────────┘
         │
         │ (backup layer)
         │
┌────────▼────────────────────────────────────────────────────────────┐
│  TIER 3: LOCAL STORAGE (Documents + UserDefaults)                  │
│  ────────────────────────────────────────────────────────────────── │
│  ⚠️  Audio files (Documents/)                                       │
│  ⚠️  Profile JSON (Documents/)                                       │
│  ⚠️  Storybook JSON (UserDefaults)                                  │
│  ⚠️  Generated PDFs (Documents/)                                    │
│  └─ Lost on app deletion, but some data recoverable from Tier 1     │
└─────────────────────────────────────────────────────────────────────┘
```

## 🔄 Data Flow Diagram

```
USER ACTION
    │
    ├─ Record Memory
    │     │
    │     ├─► Save Audio File → Documents/{UUID}.caf
    │     │                              │
    │     │                              └─► Also saved to Core Data binary
    │     │
    │     └─► Create MemoryEntry → Core Data
    │                                       │
    │                                       └─► Auto-sync to CloudKit
    │
    ├─ Add Photos
    │     │
    │     └─► Create Photo → Core Data
    │                           │
    │                           └─► Auto-sync to CloudKit
    │
    ├─ Create Profile
    │     │
    │     ├─► Save to Documents/profiles.json
    │     │         │
    │     │         └─► Backup to iCloud KVS
    │     │
    │     └─► Save to iCloud KVS (individual fields)
    │
    └─ Generate Storybook
          │
          ├─► Save to UserDefaults
          │     │
          │     └─► ⚠️  NOT backed up to iCloud
          │
          └─► Settings saved to iCloud KVS
```

## ✅ App Update Scenario

```
APP UPDATE
    │
    └─► ALL DATA SURVIVES ✅
            │
            ├─ Core Data: ✅ Persists
            ├─ CloudKit: ✅ Already synced
            ├─ Documents: ✅ Persists
            ├─ UserDefaults: ✅ Persists
            └─ iCloud KVS: ✅ Persists
```

## ⚠️ App Deletion & Reinstall Scenario

```
APP DELETION
    │
    ├─► LOCAL DATA DELETED ❌
    │     ├─ Documents directory: ❌
    │     └─ UserDefaults: ❌
    │
    └─► CLOUD DATA PRESERVED ✅
          ├─ CloudKit: ✅
          └─ iCloud KVS: ✅

APP REINSTALL
    │
    ├─► RESTORE FROM CLOUDKIT ✅
    │     └─ All MemoryEntry + Photo entities restored
    │
    ├─► RESTORE FROM ICLOUD KVS ✅
    │     └─ Profiles + Settings restored
    │
    └─► RECOVER LOCAL FILES ⚠️
          └─ Audio files recreated from Core Data binary
```

## 🎯 Quick Decision Tree

```
Is data critical for user?
    │
    ├─ YES → Is it in CloudKit or iCloud KVS?
    │          │
    │          ├─ YES → ✅ Survives deletion
    │          │
    │          └─ NO → ❌ Lost on deletion
    │
    └─ NO → Stored locally only
              │
              └─ ❌ Lost on deletion
```

## 📋 Storage Summary Table

| Data Type | Storage Location | Survives Deletion? | Survives Update? | Syncs Across Devices? |
|-----------|-----------------|-------------------|-----------------|----------------------|
| **Memory Entries** | Core Data + CloudKit | ✅ Yes | ✅ Yes | ✅ Yes |
| **Photos** | Core Data + CloudKit | ✅ Yes | ✅ Yes | ✅ Yes |
| **Audio Data** | Core Data (binary) | ✅ Yes | ✅ Yes | ✅ Yes |
| **Audio Files** | Documents/ | ❌ No* | ✅ Yes | ❌ No |
| **Profiles** | Documents/ + iCloud KVS | ✅ Yes** | ✅ Yes | ✅ Yes |
| **Storybook Content** | UserDefaults | ❌ No | ✅ Yes | ❌ No |
| **Storybook Settings** | iCloud KVS | ✅ Yes | ✅ Yes | ✅ Yes |
| **Generated PDFs** | Documents/ | ❌ No | ✅ Yes | ❌ No |
| **Onboarding State** | UserDefaults + iCloud KVS | ✅ Yes | ✅ Yes | ✅ Yes |

\* File paths invalid, but binary backup exists in Core Data  
\*\* Restored from iCloud KVS backup

## 🔑 Key Takeaways

1. **✅ Core memories are SAFE** - All memory entries persist via CloudKit
2. **✅ Profiles are SAFE** - Triple backup strategy (local + iCloud KVS)
3. **✅ Audio is SAFE** - Binary backup in Core Data can recreate files
4. **⚠️ Storybooks are NOT backed up** - But can regenerate from memories
5. **❌ Generated PDFs are temporary** - Can regenerate anytime

**Overall:** Your app has excellent data persistence! The most important data (memories, photos, profiles) all survive app deletion and sync across devices.










