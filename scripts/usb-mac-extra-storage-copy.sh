#!/bin/bash
# Copy-only: adds a NEW folder on the USB. Does NOT erase the stick or delete anything on the Mac.
# Run in Terminal.app on your Mac Mini (not from Cursor if /Volumes is blocked):
#   chmod +x scripts/usb-mac-extra-storage-copy.sh
#   ./scripts/usb-mac-extra-storage-copy.sh
#
# Skips paths that are missing. FAT32: any single file > 4GB will cause rsync errors for that file.
# Does NOT touch: Memoir*, Apologist*, Gary*/RN_Gary/llama*, Xcode ~/Library/Developer, DerivedData,
# Spitfire, Splice, Clarity_Root, Text Memes*, Music, VSPlayground, MemoirV, swift-coreml-transformers, Test.

set -euo pipefail

USB="${USB_VOLUME:-/Volumes/USB DISK}"
if [[ ! -d "$USB" ]]; then
  echo "ERROR: USB not mounted at: $USB"
  echo "Set USB_VOLUME if the volume name differs, e.g.: USB_VOLUME=\"/Volumes/MyStick\" $0"
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$USB/MacExtraStorage-$STAMP"
mkdir -p "$DEST"

echo "Destination (new folder only, existing stick data untouched): $DEST"
echo ""

# Any file > ~4 GiB cannot exist on FAT32. Avoid find|head (breaks under set -o pipefail).
have_big_file() {
  local root="$1"
  find "$root" -type f -size +4G -print -quit 2>/dev/null | grep -q .
}

copy_tree() {
  local src="$1"
  local name
  name="$(basename "$src")"
  if [[ ! -e "$src" ]]; then
    echo "Skip (missing): $src"
    return 0
  fi
  if have_big_file "$src"; then
    echo "Skip (contains file > ~4GB, unsafe for FAT32): $src"
    return 0
  fi
  echo ">>> rsync: $src -> $DEST/$name/ (excludes node_modules, build artifacts)"
  mkdir -p "$DEST/$name"
  rsync -avh --progress \
    --exclude 'node_modules/' \
    --exclude 'bower_components/' \
    --exclude '.pnpm-store/' \
    --exclude '.yarn/cache/' \
    --exclude '.next/' \
    --exclude '.nuxt/' \
    --exclude '__pycache__/' \
    --exclude '.pytest_cache/' \
    "$src/" "$DEST/$name/"
}

# --- Allowlist: folders ---
for src in \
  "$HOME/VS" \
  "$HOME/CVResearch" \
  "$HOME/nltk_data" \
  "$HOME/221" \
  "$HOME/leyk-csce221-exercise-iterators" \
  "$HOME/leyk-csce221-assignment-vector"
do
  copy_tree "$src"
done

# --- Single file ---
if [[ -f "$HOME/firebase-debug.log" ]]; then
  if [[ "$(stat -f%z "$HOME/firebase-debug.log" 2>/dev/null || echo 0)" -gt 4294967296 ]]; then
    echo "Skip firebase-debug.log (>4GB)"
  else
    echo ">>> cp: ~/firebase-debug.log"
    cp -p "$HOME/firebase-debug.log" "$DEST/"
  fi
fi

echo ""
echo "Done. Contents of new folder:"
ls -lah "$DEST"
echo ""
df -h /System/Volumes/Data || true
