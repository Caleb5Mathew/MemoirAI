# Kids Book Print Parity Checklist

Target output: `11 x 8.5 in` (`792 x 612 pt`) landscape.

## Acceptance Checklist

- [ ] Preview aspect ratio matches `792:612` with no stretch.
- [ ] Exported PDF page size is exactly `792 x 612 pt` for every page.
- [ ] Exported Photos pages are rendered from the same SwiftUI print renderer as PDF.
- [ ] Title/text blocks fit inside page margins with no clipping on all pages.
- [ ] QR code remains visible and within safe margins on illustration + text pages.
- [ ] Re-downloaded historical `bookVersionId` exports at identical dimensions.

## Quick Validation Procedure

1. Generate a kids book and open preview in app.
2. Export PDF and verify dimensions in a PDF inspector.
3. Export Photos and compare one page pixel ratio against PDF render.
4. Pull the same `bookVersionId` from Firebase and re-export; compare results.

