# Print Order Workflow

This workflow uses immutable `bookVersionId` artifacts so production printing matches what the user approved.

## Retrieval Steps

1. Identify the target `bookVersionId` from the order payload.
2. Authenticate as the correct Firebase user namespace owner.
3. Load the canonical record with `FirestoreSyncService.fetchBookVersion(bookVersionId:)`.
4. Render/export via `StoryPageViewModel.exportBookVersionPDF(bookVersionId:)`.
5. Print the generated PDF directly (no page regeneration or style changes).

## Required Record Fields

Each `BookVersionRecord` includes immutable print metadata:

- `pageWidth`
- `pageHeight`
- `orientation`
- `trimSizeInches`
- `layoutVersion`

If a record is missing any required print metadata, reject the order for manual review.

## Determinism Rules

- Never regenerate artwork or text at print time.
- Never recalculate page dimensions from UI screen size.
- Always render from stored `BookVersionRecord` + stored page image URLs.

