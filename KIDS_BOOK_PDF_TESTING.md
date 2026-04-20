# Kids Book PDF Pipeline - Testing Guide

## What Was Fixed

1. **Page rendering**: `renderCurrentBookPagesAsImages()` now properly renders ALL pages (text + illustration) at print resolution (792x612 pt for kids). The View snapshot includes `layoutIfNeeded()` for correct layout.

2. **Sync artifacts**: `syncBook` ensures every page gets an uploaded artifact:
   - Prefers `renderedPageImages` from the device (full visual parity)
   - Fallback for text pages: `fallbackTextPageImage` (never skips; uses placeholder for empty text)
   - Fallback for illustrations: persisted `imageData` (legacy migration)
   - Last resort: blank placeholder so no page is written without storage paths

3. **renderStatus**: Firestore documents always include `renderStatus: "pending"` so the Cloud Function knows to process them.

## How to Test End-to-End

### Option A: Create a New Kids Book with Dev Portal (Recommended for Testing)

1. Run the app (simulator or device) in **Debug** build
2. Sign in (or use anonymous); ensure you have a profile with at least 1 memory
3. Go to **Home** → tap **Your Book** (StoryPage)
4. Tap the **Settings** (gear) button
5. **Tap the "Settings" header text 5–7 times** (sometimes it doesn’t register, tap a bunch)
6. Developer portal sheet appears → enter password: **`Apologist123!`** → tap **Unlock**
7. In Settings:
   - **Art Style**: select **Kid's Book**
   - **Style Reference**: select **Normal**
   - Other settings can stay default
8. Tap **Back** to dismiss Settings
9. Tap **Create My Storybook**
10. In Profile Setup:
    - **Add Head-shot** (required – choose from library or camera)
    - **Ethnicity / Race**: type **Indian**
    - Gender: optional
11. Tap **Review Settings** (or proceed to generate)
12. Complete generation; verify PDF in Firebase

**Note**: The dev portal gives 2000 images (unlimited for testing). Only available in Debug builds.

### Option B: Create a New Kids Book (Standard Flow)

1. Run the app (simulator or device)
2. Sign in (or use anonymous)
3. Select a profile with at least 2 memories
4. Go to Storybook, ensure "Kids" art style is selected
5. Tap "Create My Storybook" and complete generation
6. After generation, the app calls `persistStorybook` → `queueBookSync` with rendered page images
7. Check Firebase Console:
   - Firestore: `users/{uid}/bookVersions/{bookId}` should have `renderStatus: "pending"` then `"rendered"`
   - Storage: `users/{uid}/bookVersions/{bookId}/pages/page_000.png`, `page_001.png`, etc.
   - Storage: `users/{uid}/bookVersions/{bookId}/book.pdf` (after Cloud Function runs)
8. PDF should be ready within ~30–60 seconds

### Option C: Use Admin Script (Requires gcloud)

```bash
# One-time setup
gcloud auth application-default login

cd functions
node scripts/admin-book-pdf.js list                     # List books
node scripts/admin-book-pdf.js status <bookVersionId>   # Check status
node scripts/admin-book-pdf.js trigger <bookVersionId>  # Generate PDF
node scripts/admin-book-pdf.js download <bookVersionId> # Download PDF
node scripts/admin-book-pdf.js verify <bookVersionId>   # Download, validate structure, report pass/fail
```

**Note**: Existing books in Firebase may have text pages without storage paths. The admin script's `trigger` will fail for those. Only newly created books (after this fix) or books that have been re-synced will have all page artifacts.

### Option D: Verify via Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com) → memoirai-7db06
2. Firestore → `users` → pick a user → `bookVersions`
3. Open a book document:
   - `renderStatus` should be `"pending"` or `"rendered"`
   - `pages` array: each page should have `imageStoragePath` or `renderedPageStoragePath`
4. Storage → browse to `users/{uid}/bookVersions/{bookId}/`
   - `pages/` folder should have `page_000.png`, `page_001.jpg`, etc.
   - `book.pdf` should appear after the Cloud Function runs

### Automated UI Test

`KidsBookDevPortalFlowTests.testKidsBookDevPortalFlow()` automates the dev-portal flow:
- Navigate to Your Book → Settings → tap "Settings" 5× → unlock with `Apologist123!` → Kid's Book + Normal → Create My Storybook → set ethnicity Indian

**Run script** (bypasses MCP RunSomeTests schema bug):
```bash
./scripts/run-kids-book-ui-test.sh
```
Or from project root: `bash scripts/run-kids-book-ui-test.sh`

**Alternatively**, run in Xcode: **Product → Test** (with MemoirAIUITests selected), or:
```bash
xcodebuild test -scheme MemoirAI -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:MemoirAIUITests/KidsBookDevPortalFlowTests/testKidsBookDevPortalFlow \
  -resultBundlePath /tmp/MemoirAI-TestResult.xcresult
```

Requires a booted simulator. The test stops at ProfileSetup (headshot required to proceed).

### Firebase Verification Pipeline

After creating a book (manually or via app):

1. **List books** to get `bookVersionId`:
   ```bash
   cd functions && node scripts/admin-book-pdf.js list
   ```
2. **Check status** (optional):
   ```bash
   node scripts/admin-book-pdf.js status <bookVersionId>
   ```
3. **Download PDF**:
   ```bash
   node scripts/admin-book-pdf.js download <bookVersionId> ./output/book.pdf
   ```
4. **Verify PDF** (page count, dimensions, structure):
   ```bash
   node scripts/admin-book-pdf.js verify <bookVersionId>
   ```

### One-Command Fetch (after gcloud auth)

```bash
./scripts/fetch-latest-pdf.sh ./output/mybook.pdf
```

**One-time setup**:
1. Install gcloud: `brew install --cask google-cloud-sdk`
2. Add to PATH (if needed): `export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"`
3. Login: `gcloud auth application-default login`
4. Set quota project (fixes FAILED_PRECONDITION): `gcloud auth application-default set-quota-project memoirai-7db06`

The admin script uses a fallback when the Firestore collection group index is not yet deployed: it iterates users and merges bookVersions. To use the native collection group query, deploy indexes: `firebase deploy --only firestore:indexes`.

## Expected Output

- **Kids book dimensions**: 11" × 8.5" (792 × 612 pt)
- **Page images**: 3300 × 2550 px (300 DPI) in Storage
- **PDF size**: ~15–25 MB per book (4 pages)
