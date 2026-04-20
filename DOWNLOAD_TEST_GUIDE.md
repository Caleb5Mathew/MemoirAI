# Book Download Testing Guide

## Overview
This guide helps you test and verify that book downloads create PDF pages that match the book preview exactly.

## How It Works

### 1. Download Flow
```
User clicks Download → JavaScript captures pages → Swift creates PDF → User saves file
```

### 2. Technical Details

**JavaScript Side (flipbook.js)**
- Uses `html2canvas` library to capture screenshots of each page
- Each page is captured at high resolution (3x scale)
- Quality settings: JPEG at 0.95 quality
- Dimensions:
  - Regular books: 1200×1600px (portrait, 4:3 ratio)
  - Kids books: 1920×1080px (landscape, 16:9 ratio)

**Swift Side (BookDownloadManager.swift)**
- Receives base64-encoded images from JavaScript
- Converts each image to a PDF page
- Creates a multi-page PDF document
- Presents save dialog to user

## Testing Steps

### Step 1: Verify html2canvas is Loaded
1. Build and run the app
2. Navigate to "Create your book" or "Your book" preview
3. Open the flipbook view
4. Check Xcode console for this message:
   ```
   Flipbook: html2canvas library loaded successfully
   ```

### Step 2: Test Download to Files
1. Click the download button (arrow down icon)
2. Select "Save to Files"
3. Wait for capture process (you'll see pages flipping automatically)
4. Check console for these messages:
   ```
   Flipbook: Starting PDF download with page capture...
   Flipbook: Capturing 10 pages...
   Flipbook: Capturing page 1 of 10
   ...
   Flipbook: All pages captured successfully
   Flipbook: Sent captured pages to Swift for PDF generation
   ```
5. Choose save location in Files app
6. Verify PDF is created

### Step 3: Test Download to Photos
1. Click the download button
2. Select "Save to Photos"
3. Grant photo library permission if prompted
4. Wait for capture process
5. Check Photos app for individual page images

### Step 4: Verify PDF Quality
Open the downloaded PDF and check:
- [ ] Each page matches the preview exactly
- [ ] Text is crisp and readable
- [ ] Images are clear (no pixelation)
- [ ] Fonts and spacing match preview
- [ ] Page orientation is correct (portrait vs landscape)
- [ ] All pages are included
- [ ] No blank or corrupted pages

## Common Issues & Solutions

### Issue: "html2canvas library not loaded"
**Solution:** Check that `html2canvas.min.js` is in the Xcode project:
- Path: `MemoirAI/Resources/FlipbookBundle/html2canvas.min.js`
- File size should be ~194KB
- Verify it's included in "Copy Bundle Resources" build phase

### Issue: PDF pages are blank
**Possible causes:**
1. html2canvas failed to capture
2. Page elements not rendering
3. Timing issue (not waiting for page flip)

**Debug:**
```javascript
// Add to flipbook.js after capture
console.log('Canvas size:', canvas.width, canvas.height);
console.log('Image data length:', imageData.length);
```

### Issue: Pages are cut off or wrong size
**Check:**
1. Container dimensions in console logs
2. Book size calculation in Swift
3. CSS styling for `.flipbook-page`

### Issue: Download hangs or never completes
**Check:**
1. All pages can be navigated to
2. No JavaScript errors in console
3. Memory usage (too many pages can cause issues)

## Debug Console Commands

Run these in Safari Web Inspector (connect to simulator):

### Check if html2canvas is loaded
```javascript
typeof html2canvas !== 'undefined'
// Should return: true
```

### Check page count
```javascript
window.pageFlip.getPageCount()
// Should return: number of pages
```

### Manually trigger download
```javascript
window.downloadPDF(false) // false = regular book, true = kids book
```

### Check current page
```javascript
window.pageFlip.getCurrentPageIndex()
```

## Expected Console Output (Normal Flow)

```
Flipbook: DOM loaded
Flipbook: Container element: [object HTMLDivElement]
Flipbook: JavaScript ready message received
Flipbook: Pages rendered successfully
Flipbook: Loaded 10 pages

[User clicks download]

Flipbook: Starting PDF download with page capture... Kids book: false
Flipbook: Capturing 10 pages...
Flipbook: Capturing page 1 of 10
Flipbook: Capturing element: flipbook-page cover-page
Flipbook: Using regular book dimensions: 1200x1600
Flipbook: Capturing page 2 of 10
Flipbook: Capturing element: flipbook-page
Flipbook: Using regular book dimensions: 1200x1600
[... continues for all pages ...]
Flipbook: All pages captured successfully
Flipbook: Sent captured pages to Swift for PDF generation
BookDownloadHandler: Processing 10 pages
BookDownloadHandler: Page 1 decoded successfully
[... continues for all pages ...]
BookDownloadHandler: PDF created with 10 pages
```

## Performance Notes

- Each page capture takes ~800ms (includes flip animation)
- 10-page book: ~8-10 seconds total
- 50-page book: ~40-50 seconds total
- High-quality images increase file size (expect 500KB-2MB per page)

## File Size Expectations

### Per Page:
- Regular book (1200×1600): ~500KB-800KB
- Kids book (1920×1080): ~600KB-1MB

### Total PDF:
- 10 pages: 5-8 MB
- 20 pages: 10-16 MB
- 50 pages: 25-40 MB

## Troubleshooting Checklist

- [ ] html2canvas.min.js is in bundle
- [ ] FlipbookBundle is added to Xcode project
- [ ] "Copy Bundle Resources" includes all flipbook files
- [ ] WebView JavaScript is enabled
- [ ] No CORS or security errors in console
- [ ] Sufficient memory available
- [ ] All pages render correctly before download
- [ ] Download button triggers JavaScript function

## Contact Points in Code

### JavaScript Entry Point
```javascript
// File: flipbook.js, line ~230
window.downloadPDF = async function(isKidsBook = false) {
```

### Swift Entry Point
```swift
// File: FlipbookView.swift, line ~508
case "downloadPDF":
    if let pages = body["pages"] as? [String],
       let filename = body["filename"] as? String {
        handlePDFDownload(pages: pages, filename: filename)
    }
```

### PDF Creation
```swift
// File: BookDownloadManager.swift, line ~236
static func handlePDFDownload(pages: [String], filename: String, presentingView: UIViewController?, isKidsBook: Bool = false)
```

## Success Criteria

✅ **Download works if:**
1. No JavaScript errors in console
2. All pages captured (count matches total)
3. PDF file is created
4. File size is reasonable (not 0 bytes, not >100MB)
5. PDF opens without errors
6. Each page matches the preview visually
7. Text is readable and not blurry
8. Images appear correctly

## Next Steps If Issues Found

1. **Check Xcode console** for error messages
2. **Enable Safari Web Inspector** to debug JavaScript
3. **Add debug logging** to capture process
4. **Test with fewer pages** to isolate issues
5. **Check memory warnings** in Xcode
6. **Verify FlipbookBundle files** are in build

---

*Last Updated: 2025-10-30*










