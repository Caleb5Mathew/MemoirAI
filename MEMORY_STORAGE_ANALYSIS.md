# Memory Storage & Persistence Analysis

## 📊 Complete Storage Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         MEMOIRAI DATA STORAGE                           │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ 1. CORE DATA + CLOUDKIT (Primary Storage)                               │
│    Container: iCloud.com.Buildr.MemoirAI                                │
│    ──────────────────────────────────────────────────────────────────── │
│                                                                          │
│    ✅ MEMORY ENTRIES (MemoryEntry Entity)                               │
│       ├─ id: UUID                                                        │
│       ├─ prompt: String                                                  │
│       ├─ text: String (transcription)                                    │
│       ├─ audioFileURL: String (path to file)                            │
│       ├─ audioData: Binary (backup copy)                                 │
│       ├─ createdAt: Date                                                 │
│       ├─ profileID: UUID                                                  │
│       ├─ chapter: String                                                 │
│       ├─ characterDetails: String                                       │
│       └─ photos: [Photo] (relationship)                                  │
│                                                                          │
│    ✅ PHOTOS (Photo Entity)                                             │
│       ├─ id: UUID                                                        │
│       ├─ data: Binary (allowsExternalBinaryDataStorage)                  │
│       └─ memoryEntry: MemoryEntry (relationship)                         │
│                                                                          │
│    🔄 SYNC STATUS:                                                       │
│       └─ Syncs to CloudKit automatically                                 │
│       └─ Survives app deletion/reinstall ✅                              │
│       └─ Syncs across devices ✅                                          │
│       └─ Requires same iCloud account                                    │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ 2. FILE SYSTEM (Documents Directory)                                    │
│    Location: ~/Documents/ (app sandbox)                                  │
│    ──────────────────────────────────────────────────────────────────── │
│                                                                          │
│    ✅ AUDIO FILES                                                         │
│       ├─ Format: .caf (uncompressed PCM)                                 │
│       ├─ Location: Documents/{UUID}.caf                                  │
│       ├─ Quality: 44.1kHz, 32-bit PCM                                    │
│       └─ Also stored in Core Data as binary backup                        │
│                                                                          │
│    ✅ PROFILE DATA                                                        │
│       └─ profiles.json (JSON encoded Profile array)                      │
│                                                                          │
│    ✅ GENERATED PDFs                                                      │
│       └─ MemoirAI_Storybook_{timestamp}.pdf                             │
│                                                                          │
│    ⚠️  PERSISTENCE STATUS:                                               │
│       └─ Survives app updates ✅                                         │
│       └─ DELETED when app is uninstalled ❌                              │
│       └─ NOT synced to iCloud (unless backed up elsewhere)              │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ 3. USERDEFAULTS (Local Preferences)                                     │
│    Location: App's UserDefaults plist                                    │
│    ──────────────────────────────────────────────────────────────────── │
│                                                                          │
│    ✅ STORYBOOK DATA                                                      │
│       ├─ storybook_{profileID}: Data (current book)                      │
│       └─ storybook_history_{profileID}: [Data] (all books)              │
│                                                                          │
│    ✅ UI PREFERENCES                                                      │
│       ├─ memoirPageCount: Int                                            │
│       ├─ memoirArtStyle: String                                          │
│       ├─ memoirCustomArtStyleText: String                                │
│       ├─ memoirEthnicity: String                                         │
│       ├─ memoirGender: String                                            │
│       ├─ memoirOtherPersonalDetails: String                              │
│       ├─ selectedProfileIndex: Int                                       │
│       ├─ memoirai_freeBookUsed: Bool                                      │
│       ├─ memoirai_rc_user_id: String                                      │
│       └─ Various prompt completion flags                                 │
│                                                                          │
│    ✅ CHARACTER DETAILS BACKUP                                           │
│       └─ characterDetails_{memoryID}: String (JSON backup)               │
│                                                                          │
│    ⚠️  PERSISTENCE STATUS:                                               │
│       └─ Survives app updates ✅                                         │
│       └─ DELETED when app is uninstalled ❌                              │
│       └─ NOT synced across devices (unless backed up to iCloud KVS)     │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ 4. ICLOUD KEY-VALUE STORE (Cross-Device Backup)                         │
│    Container: $(TeamIdentifierPrefix)$(CFBundleIdentifier)             │
│    ──────────────────────────────────────────────────────────────────── │
│                                                                          │
│    ✅ PROFILE BACKUPS                                                     │
│       ├─ memoir_profiles_backup: Data (full profiles JSON)              │
│       ├─ memoir_selectedProfileIndex: Int                                │
│       └─ memoir_profile_{profileID}_*: Individual profile fields        │
│                                                                          │
│    ✅ STORYBOOK SETTINGS                                                 │
│       ├─ memoir_pageCount: Int                                           │
│       ├─ memoir_artStyle: String                                         │
│       ├─ memoir_customArtStyleText: String                               │
│       ├─ memoir_ethnicity: String                                        │
│       ├─ memoir_gender: String                                           │
│       └─ memoir_otherPersonalDetails: String                             │
│                                                                          │
│    ✅ ONBOARDING STATE                                                    │
│       └─ hasCompletedOnboarding: Bool                                    │
│                                                                          │
│    ✅ UI PREFERENCES                                                     │
│       └─ Various camera wiggle, prompt completion flags                 │
│                                                                          │
│    🔄 SYNC STATUS:                                                       │
│       └─ Syncs to iCloud automatically                                   │
│       └─ Survives app deletion/reinstall ✅                              │
│       └─ Syncs across devices ✅                                          │
│       └─ Limited to 1MB total storage                                     │
│       └─ Requires same iCloud account                                    │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ 5. TEMPORARY FILES                                                      │
│    Location: NSTemporaryDirectory()                                     │
│    ──────────────────────────────────────────────────────────────────── │
│                                                                          │
│    ⚠️  PDF PREVIEWS                                                      │
│       └─ Temporary PDF files for download                                │
│                                                                          │
│    ⚠️  PERSISTENCE STATUS:                                               │
│       └─ DELETED when app closes or system cleans up ❌                  │
│       └─ Should NOT be relied upon for persistence                       │
└─────────────────────────────────────────────────────────────────────────┘
```

## 🔄 Data Flow & Persistence by Scenario

### Scenario 1: App Update
```
✅ SURVIVES:
   ├─ Core Data + CloudKit (synced to iCloud)
   ├─ File System (Documents directory)
   ├─ UserDefaults (local preferences)
   └─ iCloud Key-Value Store (cross-device backup)

⚠️  NOTES:
   └─ All data should persist through updates
```

### Scenario 2: App Deletion & Reinstall
```
✅ SURVIVES (via iCloud):
   ├─ Core Data + CloudKit
   │  └─ MemoryEntry (text, metadata)
   │  └─ Photo (image data)
   │  └─ Relationships
   │
   ├─ iCloud Key-Value Store
   │  └─ Profile data (backup)
   │  └─ Selected profile index
   │  └─ Storybook settings
   │  └─ Onboarding state
   │
   └─ Profile metadata (via iCloud KVS backup)

❌ LOST:
   ├─ Audio files in Documents directory
   │  └─ BUT: Core Data has audioData binary backup
   │  └─ Recovery: Core Data binary can recreate files
   │
   ├─ Local UserDefaults (not synced)
   │  └─ Storybook JSON data
   │  └─ Character details backup
   │
   └─ Generated PDFs in Documents directory
```

### Scenario 3: Device Change (Same iCloud Account)
```
✅ SYNCED AUTOMATICALLY:
   ├─ Core Data + CloudKit
   │  └─ All memory entries
   │  └─ All photos
   │  └─ All relationships
   │
   └─ iCloud Key-Value Store
      └─ Profile data
      └─ Settings
      └─ Preferences

⚠️  REQUIRES MANUAL ACTION:
   └─ Audio files (need to be recreated from Core Data binary)
   └─ Generated PDFs (not synced, need to regenerate)
```

## 📋 Detailed Storage Breakdown

### Memory Entry Storage
```
┌─────────────────────────────────────────────────────────┐
│ MemoryEntry Entity (Core Data + CloudKit)              │
├─────────────────────────────────────────────────────────┤
│ Field              │ Storage Location      │ Persists? │
├────────────────────┼───────────────────────┼───────────┤
│ id                 │ Core Data + CloudKit  │ ✅ Yes    │
│ prompt             │ Core Data + CloudKit  │ ✅ Yes    │
│ text               │ Core Data + CloudKit  │ ✅ Yes    │
│ audioFileURL       │ Core Data + CloudKit  │ ✅ Yes*   │
│ audioData          │ Core Data + CloudKit  │ ✅ Yes    │
│ createdAt          │ Core Data + CloudKit  │ ✅ Yes    │
│ profileID          │ Core Data + CloudKit  │ ✅ Yes    │
│ chapter            │ Core Data + CloudKit  │ ✅ Yes    │
│ characterDetails   │ Core Data + CloudKit  │ ✅ Yes    │
│ photos (rel)       │ Core Data + CloudKit  │ ✅ Yes    │
└─────────────────────────────────────────────────────────┘

* audioFileURL path may be invalid after reinstall, but audioData binary
  backup exists in Core Data and can recreate the file
```

### Audio File Storage (Dual Storage)
```
┌─────────────────────────────────────────────────────────┐
│ Audio Storage Strategy                                  │
├─────────────────────────────────────────────────────────┤
│ Location 1: Documents Directory                         │
│   └─ File: {UUID}.caf                                   │
│   └─ Format: Uncompressed PCM (44.1kHz, 32-bit)        │
│   └─ Persists: ❌ Lost on app deletion                  │
│                                                                          │
│ Location 2: Core Data Binary                            │
│   └─ Field: MemoryEntry.audioData                       │
│   └─ Format: Binary Data                                │
│   └─ Persists: ✅ Survives via CloudKit                 │
│                                                                          │
│ Recovery: If file missing, app can recreate from binary │
└─────────────────────────────────────────────────────────┘
```

### Profile Storage (Triple Backup)
```
┌─────────────────────────────────────────────────────────┐
│ Profile Storage Strategy                                │
├─────────────────────────────────────────────────────────┤
│ Backup 1: Documents Directory                           │
│   └─ File: profiles.json                                │
│   └─ Format: JSON encoded [Profile]                    │
│   └─ Persists: ❌ Lost on app deletion                  │
│                                                                          │
│ Backup 2: iCloud Key-Value Store                        │
│   └─ Key: memoir_profiles_backup                       │
│   └─ Format: JSON encoded [Profile]                     │
│   └─ Persists: ✅ Survives app deletion                 │
│                                                                          │
│ Backup 3: Individual Profile Fields (iCloud KVS)        │
│   └─ Keys: memoir_profile_{ID}_name, _birthdate, etc.   │
│   └─ Persists: ✅ Survives app deletion                 │
│                                                                          │
│ Recovery: Loads from iCloud KVS if local file missing   │
└─────────────────────────────────────────────────────────┘
```

### Storybook Storage
```
┌─────────────────────────────────────────────────────────┐
│ Storybook Storage                                       │
├─────────────────────────────────────────────────────────┤
│ Current Book:                                           │
│   └─ UserDefaults: storybook_{profileID}               │
│   └─ Format: JSON (PersistableStorybook)                │
│   └─ Persists: ❌ Lost on app deletion                  │
│                                                                          │
│ History:                                                │
│   └─ UserDefaults: storybook_history_{profileID}       │
│   └─ Format: [Data] (array of JSON)                     │
│   └─ Persists: ❌ Lost on app deletion                  │
│                                                                          │
│ Settings (Backed up to iCloud KVS):                     │
│   ├─ Page count, art style, ethnicity, gender, etc.     │
│   └─ Persists: ✅ Survives app deletion                 │
│                                                                          │
│ ⚠️  NOTE: Storybook content NOT backed up to iCloud    │
│    Only settings are backed up                          │
└─────────────────────────────────────────────────────────┘
```

## ⚠️ Critical Findings

### What WILL Survive App Deletion/Reinstall:
1. ✅ **Memory Entries** (via CloudKit)
   - All text, prompts, metadata
   - All relationships
   - Photo data

2. ✅ **Audio Data** (via Core Data binary)
   - Stored as binary in Core Data
   - Can recreate files from binary

3. ✅ **Profile Data** (via iCloud KVS)
   - Names, photos, birthdates
   - Profile selection index

4. ✅ **Settings** (via iCloud KVS)
   - Storybook preferences
   - Onboarding state
   - UI preferences

### What WON'T Survive App Deletion/Reinstall:
1. ❌ **Audio Files** (Documents directory)
   - File paths become invalid
   - BUT: Can be recreated from Core Data binary

2. ❌ **Storybook Content** (UserDefaults)
   - Generated storybook JSON not backed up
   - Settings ARE backed up (can regenerate)

3. ❌ **Generated PDFs** (Documents directory)
   - Need to regenerate from storybook

4. ❌ **Local UserDefaults** (not synced)
   - Character details backup
   - Various local flags

## 🔧 Recommendations

### Current State: GOOD ✅
- Core memory data persists via CloudKit
- Profile data has triple backup strategy
- Audio has binary backup in Core Data

### Potential Improvements:
1. **Storybook Persistence**
   - Consider backing up storybook JSON to iCloud KVS or CloudKit
   - Or regenerate from memory entries on restore

2. **Audio File Recovery**
   - Implement automatic recovery from binary data
   - Check audioFileURL existence, recreate if missing

3. **PDF Storage**
   - Consider saving generated PDFs to Files app (user's choice)
   - Or document that PDFs are temporary and can be regenerated

## 📊 Summary Graph

```
                    ┌─────────────────────────────┐
                    │   USER CREATES MEMORY        │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  SAVE TO CORE DATA          │
                    │  (MemoryEntry + Photo)      │
                    └──────────────┬──────────────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            │                      │                      │
    ┌───────▼────────┐    ┌───────▼────────┐   ┌───────▼────────┐
    │  CLOUDKIT SYNC │    │  LOCAL FILE     │   │  USERDEFAULTS  │
    │  (Primary)     │    │  (Audio)        │   │  (Settings)    │
    └───────┬────────┘    └────────────────┘   └───────┬────────┘
            │                                            │
            │                     ┌──────────────────────┘
            │                     │
    ┌───────▼─────────────────────▼────────┐
    │   ICLOUD KEY-VALUE STORE              │
    │   (Backup for Profiles & Settings)    │
    └───────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  APP DELETION/REINSTALL SCENARIO                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ✅ RESTORED FROM CLOUDKIT:                                 │
│     ├─ MemoryEntry entities                                  │
│     ├─ Photo entities                                        │
│     └─ Relationships                                          │
│                                                              │
│  ✅ RESTORED FROM ICLOUD KVS:                               │
│     ├─ Profile data                                          │
│     ├─ Profile selection                                     │
│     └─ Settings                                              │
│                                                              │
│  ⚠️  RECOVERABLE:                                            │
│     └─ Audio files (from Core Data binary)                  │
│                                                              │
│  ❌ LOST:                                                     │
│     ├─ Local audio files (paths invalid, but binary exists)  │
│     ├─ Storybook JSON (not backed up)                        │
│     └─ Generated PDFs                                         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 🎯 Final Answer

**Will data survive app deletion/reinstall?**

**YES** - Most critical data survives:
- ✅ All memory entries (text, metadata, photos)
- ✅ Audio data (as binary in Core Data)
- ✅ Profile information
- ✅ Settings and preferences

**NO** - Some data is lost:
- ❌ Local audio file paths (but binary exists to recreate)
- ❌ Generated storybook JSON (but can regenerate)
- ❌ Generated PDFs (but can regenerate)

**Bottom Line:** Your memories are safe! The core data persists via CloudKit, and profiles persist via iCloud Key-Value Store. Only generated/derived content (storybooks, PDFs) would need to be regenerated after reinstall.










