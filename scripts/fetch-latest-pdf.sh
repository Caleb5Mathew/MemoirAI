#!/usr/bin/env bash
#
# Fetch the most recent book PDF from Firebase.
# Requires: gcloud auth application-default login (one-time)
#
# Usage: ./scripts/fetch-latest-pdf.sh [output_path]
# Example: ./scripts/fetch-latest-pdf.sh ./output/mybook.pdf
#

set -e
cd "$(dirname "$0")/.."

# Ensure gcloud is in PATH
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:${PATH:-}"

if ! command -v gcloud &>/dev/null; then
  echo "gcloud not found. Install: brew install --cask google-cloud-sdk"
  exit 1
fi

# Check ADC
if ! gcloud auth application-default print-access-token &>/dev/null; then
  echo "Run this first: gcloud auth application-default login"
  echo "Then open the URL in your browser, sign in, paste the code."
  exit 1
fi

OUTPUT="${1:-./MemoirAI_latest.pdf}"
mkdir -p "$(dirname "$OUTPUT")"

echo "Getting latest book ID..."
cd functions
BOOK_ID=$(node scripts/admin-book-pdf.js latest 2>/dev/null) || { echo "Failed to get books. Run: gcloud auth application-default login"; exit 1; }
if [ -z "$BOOK_ID" ]; then
  echo "No books found in Firebase."
  exit 1
fi

echo "Latest book: $BOOK_ID"
echo "Downloading PDF..."
node scripts/admin-book-pdf.js download "$BOOK_ID" "$OUTPUT" || exit 1
echo ""
echo "Verifying..."
node scripts/admin-book-pdf.js verify "$BOOK_ID"
echo ""
echo "PDF saved to: $OUTPUT"
