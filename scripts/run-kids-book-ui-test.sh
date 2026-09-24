#!/usr/bin/env bash
#
# Run the Kids Book dev portal UI test.
# Bypasses MCP RunSomeTests (schema bug); uses xcodebuild directly.
#
# Usage: ./scripts/run-kids-book-ui-test.sh
# Or:    bash scripts/run-kids-book-ui-test.sh
#

cd "$(dirname "$0")/.."
RESULT_BUNDLE="/tmp/MemoirAI-TestResult.xcresult"
SIMULATOR_ID="${MEMOIRAI_SIMULATOR_ID:-$(xcrun simctl list devices booted | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | head -1)}"

if [ -z "$SIMULATOR_ID" ]; then
  echo "FAILED: boot an iOS simulator or set MEMOIRAI_SIMULATOR_ID"
  exit 1
fi

# Remove existing result bundle so xcodebuild doesn't fail
if [ -e "$RESULT_BUNDLE" ]; then
  find "$RESULT_BUNDLE" -depth -delete
fi

echo "Running Kids Book dev portal UI test..."
set -o pipefail
xcodebuild test -scheme MemoirAI \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -only-testing:MemoirAIUITests/KidsBookDevPortalFlowTests/testKidsBookDevPortalFlow \
  -resultBundlePath "$RESULT_BUNDLE" \
  2>&1 | tee /tmp/memoir-ui-test.log | tail -40
EXIT=${PIPESTATUS[0]}

echo ""
echo "--- Summary ---"
if [ $EXIT -ne 0 ] || ! [ -d "$RESULT_BUNDLE" ]; then
  echo "FAILED (exit $EXIT)"
  if [ -d "$RESULT_BUNDLE" ]; then
    echo "Failure details:"
    xcrun xcresulttool get --path "$RESULT_BUNDLE" --legacy 2>&1 | grep -oE 'XCTAssertTrue failed[^.]+' || true
  fi
  exit 1
else
  echo "PASSED"
  exit 0
fi
