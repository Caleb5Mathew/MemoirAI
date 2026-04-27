#!/bin/bash
# Copy Mac Mini "safe" folders to USB, optionally DELETE from Mac after verify (frees SSD).
#
# Run on the Mac Mini in Terminal (full path to USB):
#   cd /Users/calebm/Documents/MemoirAI
#   ./scripts/usb-mac-mini-free-space.sh
#
# To copy AND remove from Mac after checksum verify (frees space):
#   COPY_THEN_DELETE=1 ./scripts/usb-mac-mini-free-space.sh
#
# USB volume override:
#   USB_VOLUME="/Volumes/MyStick" ./scripts/usb-mac-mini-free-space.sh
#
# FAT32: skips any tree that contains a file > 4GB.
#
# NEVER touches (by design): Memoir*, Apologist*, Gary*/RN_Gary/llama*, ~/Library/Developer,
# DerivedData, Spitfire, Splice, Clarity_Root, Text Memes*, Music, VSPlayground, MemoirV,
# swift-coreml-transformers, Test, ~/Documents (entire folder — use other flows for Memoir).
#
# Biggest space elsewhere (manual / other tools): ~/Library/Developer (~tens of GB, Xcode),
# ~/Library/Application Support/Claude, Cursor — not in this script; trim simulators in Xcode if needed.

set -euo pipefail

USB="${USB_VOLUME:-/Volumes/USB DISK}"
if [[ ! -d "$USB" ]]; then
  echo "ERROR: USB not mounted at: $USB"
  exit 1
fi

COPY_THEN_DELETE="${COPY_THEN_DELETE:-0}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$USB/MacMiniOffload-$STAMP"
mkdir -p "$DEST"

echo "USB destination: $DEST"
echo "COPY_THEN_DELETE=$COPY_THEN_DELETE (set to 1 to remove from Mac after each successful verify)"
echo ""

# True if any file is larger than ~4 GiB (FAT32 single-file limit).
# Uses -print -quit (not `find | head`) so pipefail + SIGPIPE does not lie about the result.
have_big_file() {
  local root="$1"
  find "$root" -type f -size +4G -print -quit 2>/dev/null | grep -q .
}

rsync_dry_differs() {
  local src="$1"
  local dst="$2"
  local tmp
  tmp="$(mktemp)"
  rsync -avcn --checksum "$src/" "$dst/" >"$tmp" 2>&1 || true
  # Anything besides boilerplate means a difference
  grep -vE '^(sending incremental file list|sent [0-9]+ bytes|total size is|[[:space:]]*$)' "$tmp" | grep -q .
  local st=$?
  rm -f "$tmp"
  return "$st"
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
    echo "Skip (file larger than ~4GB in tree — unsafe for FAT32): $src"
    return 0
  fi

  echo ">>> COPY: $src -> $DEST/$name/"
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

  if [[ "$COPY_THEN_DELETE" == "1" ]]; then
    echo ">>> VERIFY (checksum dry-run): $src"
    if rsync_dry_differs "$src" "$DEST/$name/"; then
      echo "VERIFY FAILED — not deleting: $src"
      exit 1
    fi
    echo ">>> DELETE from Mac: $src"
    rm -rf "$src"
  fi
}

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

if [[ -f "$HOME/firebase-debug.log" ]]; then
  sz="$(stat -f%z "$HOME/firebase-debug.log" 2>/dev/null || echo 0)"
  if [[ "$sz" -gt 4294967296 ]]; then
    echo "Skip firebase-debug.log (>4GB)"
  else
    echo ">>> COPY: ~/firebase-debug.log"
    cp -p "$HOME/firebase-debug.log" "$DEST/"
    if [[ "$COPY_THEN_DELETE" == "1" ]]; then
      a="$(shasum -a 256 "$HOME/firebase-debug.log" | awk '{print $1}')"
      b="$(shasum -a 256 "$DEST/firebase-debug.log" | awk '{print $1}')"
      if [[ "$a" != "$b" ]]; then
        echo "VERIFY FAILED for firebase-debug.log"
        exit 1
      fi
      rm -f "$HOME/firebase-debug.log"
    fi
  fi
fi

echo ""
echo "Done. Listing: $DEST"
ls -lah "$DEST"
echo ""
df -h /System/Volumes/Data || true
