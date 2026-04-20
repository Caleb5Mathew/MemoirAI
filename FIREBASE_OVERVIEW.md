# MemoirAI — Firebase Architecture Overview

## Summary

MemoirAI uses **Firebase** for cloud sync, authentication, and backend services. Core Data + CloudKit handle fast local sync; Firebase provides **admin visibility**, user auth, and server-side PDF generation.

**Firebase Project:** `memoirai-7db06`  
**Storage Bucket:** `memoirai-7db06.firebasestorage.app`

---

## Services Used

| Service | Purpose |
|---------|---------|
| **Firebase Auth** | Apple Sign-In, Google Sign-In, Anonymous auth |
| **Cloud Firestore** | User documents, memories, book versions, profiles |
| **Cloud Storage** | Audio, images, book pages, PDFs |
| **Cloud Functions** | PDF packaging from stored PNG pages |

---

## Data Structure (Firestore)

```
users/{userId}
├── (user doc) — profileName, email, displayName, authProvider, lastActiveAt
├── memories/{memoryId} — prompt, transcription, audioURL, chapter, profileID, characterDetails
├── books/{bookId} — legacy metadata mirror; points to bookVersions
├── bookVersions/{bookVersionId} — canonical book record with pages, render status, PDF URL
└── profiles/{profileId} — name, birthdate
```

### Memory Document Shape

- `prompt`, `transcription`, `createdAt`, `chapter`, `profileID`, `profileName`
- `audioURL` — Firebase Storage path for audio
- `characterDetails` — JSON for image generation
- `syncedAt` — server timestamp

### Book Version Document Shape

- `bookVersionId`, `profileId`, `createdAt`, `memoryOrder`, `pageCount`
- `artStyle`, `orientation`, `pageWidth`, `pageHeight`, `trimSizeInches`, `layoutVersion`
- `pages[]` — per-page: `imageStoragePath`, `imageURL`, `renderedPageStoragePath`, `renderedPageURL`, etc.
- `renderStatus` — `pending` | `rendered` | `failed`
- `pdfURL`, `pdfStoragePath`, `pdfBytes`, `pdfPageCount`

---

## Storage Paths

| Content | Path Pattern |
|---------|--------------|
| Memory audio | `users/{userId}/audio/{memoryId}.caf` |
| Memory images | `users/{userId}/images/{memoryId}_{index}.jpg` |
| Book PDF (legacy) | `users/{userId}/books/{bookId}.pdf` |
| Book version pages | `users/{userId}/bookVersions/{bookId}/pages/page_{index}.png` (and .jpg) |
| Book version PDF | `users/{userId}/bookVersions/{bookId}/book.pdf` |

---

## Key Swift Files

| File | Role |
|------|------|
| `FirebaseConfig.swift` | `FirebaseApp.configure()`, Firestore offline cache, current user |
| `AuthenticationService.swift` | Apple/Google/anonymous sign-in, user doc creation |
| `FirestoreSyncService.swift` | Sync memories, books, profiles; fetch book versions; invoke PDF render |
| `StorageService.swift` | Upload audio, images, book pages, PDFs; uses `Auth.auth().currentUser` |

---

## Cloud Functions

**`functions/index.js`** — `generateBookVersionPdf`:

1. Verifies user via Bearer ID token
2. Reads `users/{userId}/bookVersions/{bookVersionId}` from Firestore
3. Downloads page images from Storage
4. Assembles PDF with pdf-lib
5. Uploads PDF to Storage, updates Firestore with `pdfURL`, `pdfStoragePath`, `renderStatus: "rendered"`

Called from `FirestoreSyncService.invokeBookRenderFunction()` with `BOOK_RENDER_FUNCTION_URL` from Info.plist.

---

## Security Rules (firestore.rules)

- **users/{userId}/*** — read/write only if `request.auth.uid == userId`
- **bookVersions** — update restricted when `renderStatus == "rendered"` (immutable print artifacts)
- **globalApiTelemetry/** — read/write for any authenticated user (dev telemetry)

---

## App Flow

1. **Launch** — `FBAppDelegate` calls `FirebaseConfig.shared.configure()`
2. **Auth** — `AuthenticationService` handles Apple/Google/anonymous; creates/updates `users/{uid}` in Firestore
3. **Memory save** — Core Data persists; `FirestoreSyncService.queueMemorySync()` uploads to Firestore + Storage
4. **Book save** — `FirestoreSyncService.syncBook()` uploads pages to Storage, writes `bookVersions` doc, triggers `generateBookVersionPdf`
5. **PDF** — Cloud Function packages PNGs → PDF, stores in Storage, updates Firestore

---

## Authentication Modes

- **Anonymous** — `signInAnonymouslyIfNeeded()` for automatic sync
- **Apple** — `signInWithApple(credential:)`
- **Google** — `signInWithGoogle()`, `linkGoogleAccount()` to upgrade anonymous

---

## Related Config

- **GoogleService-Info.plist** — Firebase project config (PROJECT_ID, API_KEY, etc.)
- **firebase.json** — `functions`, `firestore.rules`, `storage.rules`
- **Info.plist** — `BOOK_RENDER_FUNCTION_URL` for Cloud Function URL
