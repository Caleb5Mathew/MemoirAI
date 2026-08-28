#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
debug_entitlements="$repo_root/MemoirAI/MemoirAI.Debug.entitlements"
release_entitlements="$repo_root/MemoirAI/MemoirAI.Release.entitlements"
privacy_manifest="$repo_root/MemoirAI/PrivacyInfo.xcprivacy"
info_plist="$repo_root/MemoirAI/Info.plist"
project_file="$repo_root/MemoirAI.xcodeproj/project.pbxproj"
app_icon="$repo_root/MemoirAI/Assets.xcassets/AppIcon.appiconset/Adobe Express - file (10).png"
firebase_config="$repo_root/firebase.json"
privacy_page="$repo_root/public/privacy/index.html"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

for plist in "$debug_entitlements" "$release_entitlements" "$privacy_manifest" "$info_plist"; do
  plutil -lint "$plist" >/dev/null || fail "Invalid plist: $plist"
done

[[ "$(plutil -extract aps-environment raw -o - "$debug_entitlements")" == "development" ]] \
  || fail "Debug APNs entitlement must use development"
[[ "$(plutil -extract aps-environment raw -o - "$release_entitlements")" == "production" ]] \
  || fail "Release APNs entitlement must use production"
debug_entitlements_json="$(plutil -convert json -o - "$debug_entitlements")"
release_entitlements_json="$(plutil -convert json -o - "$release_entitlements")"
[[ "$(jq -r '.["com.apple.developer.devicecheck.appattest-environment"]' <<<"$debug_entitlements_json")" == "development" ]] \
  || fail "Debug App Attest entitlement must use development"
[[ "$(jq -r '.["com.apple.developer.devicecheck.appattest-environment"]' <<<"$release_entitlements_json")" == "production" ]] \
  || fail "Release App Attest entitlement must use production"

if rg -q 'com\.apple\.security\.|com\.apple\.developer\.aps-environment' "$debug_entitlements" "$release_entitlements"; then
  fail "iOS entitlements contain a macOS-only or duplicate APNs key"
fi

[[ "$(rg -c 'MemoirAI/MemoirAI.Debug.entitlements' "$project_file")" == "1" ]] \
  || fail "Debug entitlement file is not wired exactly once"
[[ "$(rg -c 'MemoirAI/MemoirAI.Release.entitlements' "$project_file")" == "1" ]] \
  || fail "Release entitlement file is not wired exactly once"

[[ "$(plutil -extract FacebookAutoInitEnabled raw -o - "$info_plist")" == "false" ]] \
  || fail "Meta auto-init must default to false"
[[ "$(plutil -extract FacebookAdvertiserIDCollectionEnabled raw -o - "$info_plist")" == "false" ]] \
  || fail "Meta advertiser ID collection must default to false"

privacy_json="$(plutil -convert json -o - "$privacy_manifest")"
[[ "$(jq -r '.NSPrivacyTracking' <<<"$privacy_json")" == "true" ]] \
  || fail "Privacy manifest must declare the app's Meta attribution tracking"
jq -e '.NSPrivacyTrackingDomains | index("ep1.facebook.com") != null' <<<"$privacy_json" >/dev/null \
  || fail "Privacy manifest is missing Meta's declared tracking domain"

[[ -f "$privacy_page" ]] || fail "Hosted privacy policy is missing"
jq -e '.hosting.rewrites[] | select(.source == "/privacy" and .destination == "/privacy/index.html")' \
  "$firebase_config" >/dev/null || fail "Firebase Hosting does not route /privacy"

[[ "$(sips -g pixelWidth "$app_icon" | awk '/pixelWidth/ {print $2}')" == "1024" ]] \
  || fail "App icon width must be 1024"
[[ "$(sips -g pixelHeight "$app_icon" | awk '/pixelHeight/ {print $2}')" == "1024" ]] \
  || fail "App icon height must be 1024"
[[ "$(sips -g hasAlpha "$app_icon" | awk '/hasAlpha/ {print $2}')" == "no" ]] \
  || fail "App icon must not contain an alpha channel"

echo "Release configuration gates passed."
