# Onboarding reliability and first-story refinement

Status: version 3.45/build 2026.11.03 successfully uploaded to App Store Connect on November 3, 2026 at 12:09 CST. Submitted for App Store review through Safari automation. Apple confirmed `3.45 Waiting for Review` and `1 Item Submitted`. Public release remains pending; the existing manual-release setting was retained.

Source commit: `ea9929a` on `fix/onboarding-release-isolated`.

The previous onboarding path counted closing an unavailable paywall as successful completion. This candidate separates recovery exits from successful completion, removes redundant paywall preparation requests, bounds preparation to 20 seconds, and guards late results against cancellation/account changes. Historical SDK causes remain unidentified because the old events only recorded a generic preparation failure.

Preview retries retain their original request text and identifiers, share a bounded retry budget, and distinguish recoverable errors from terminal errors. Account connection failures have a visible Reconnect screen. Saved draft recovery must be resolved before editing so newly entered words cannot silently bypass autosave. Draft cleanup preserves uncertain audio when another account's metadata is unreadable.

First-story refinements add a Write instead action, visible validation and storyteller guidance, keyboard scrolling, and safe resumption past audience/name questions already answered. Home links to the current account/profile's latest saved story. No automatic generation is introduced.

## Measurement

`analytics_version=2` separates `Onboarding Exited` from `Onboarding Completed`. `onboarding_version=native_v7` identifies the capture refinements. New events record input readiness, input method, first input per flow, preparation-ready latency, and draft recovery. No story text or names are recorded.

Compare mature seven-day cohorts with the same production/external/physical entry filters. Use unique users for reach and a separate constant-`flow_id` funnel for attempt-level diagnosis. Track personal-preview reach, offer availability and payment separately. Backgrounding does not establish abandonment. The existing 20/53 personal-preview reach is not a paid conversion rate or a measured result of this candidate.

## Isolation

Branch: `fix/onboarding-release-isolated`, based on `cda78ee`.

This candidate retains committed pricing, product selection, trial copy and allowance behavior. It excludes the working copy's earlier server allowance migration, backend/order changes and unrelated analytics. The original working tree remains intact.

## Validation

- Swift syntax and whitespace checks passed.
- Expanded original-tree run: 152 unit tests passed; one UI pre-scroll visibility assertion was corrected before candidate verification.
- Final isolated candidate: 176 unit tests (79 XCTest and 97 Swift Testing) and all four UI tests passed. Result: `/tmp/MemoirOnboardingRecoveryFinalNov03.xcresult`. Checks cover account cleanup, privacy, profile scoping, paywall/preview recovery, Home-row rendering, restored draft navigation, typing guidance and required storyteller selection.
- UI verification exposed a retained hidden/disabled Back control after restoring a draft. Recovery now removes inactive form content until restoration/reconnection, retaining model state. The regression checks passed without weakening the hit-target assertion.
- Device archive succeeded for version 3.45, build 2026.11.03. Bundle/version assertions and `codesign --verify --deep --strict` passed. App Store distribution signing and upload succeeded with automatic provisioning.
- Archive: `/Volumes/Memoir Video Workspace/MemoirVerificationNov03/Memoir-3.45-2026.11.03.xcarchive`. Upload log: `/tmp/memoir-appstore-upload-final.log`.
- App Store Connect upload: succeeded (exit 0, `EXPORT SUCCEEDED`); package processing acknowledged by Apple. Review submission completed through Safari AppleScript automation after the normal browser-control connection failed. The processed build appears as `2026.11.3` in Apple’s UI. Existing review/contact details, pricing and manual-release behavior were preserved.
- Non-blocking symbol upload warnings: prebuilt FirebaseFirestoreInternal, absl, grpc, grpcpp and openssl_grpc frameworks lack matching dSYMs. Apple accepted the app; diagnostics for frames inside these dependencies may be less informative. Memoir’s own app binary and dSYM were verified to share UUID `7AE0450E-DC9E-30B5-9A37-1813146CFCA9`.

Known limits: browser automation remains unavailable for inspecting the single historical failed-preview profile or saving Mixpanel reports. Simulator tests do not establish a real App Store purchase. No conversion uplift is claimed before rollout.

## App Store text prepared for submission

This update makes it easier to write your first story, return to an unfinished draft, and recover when a preview or subscription screen cannot load.

## Reversible build-cache cleanup

The temporary `/tmp/MemoirDeviceReleaseNov03` build cache was backed up with its parent directory to `/Volumes/Memoir Video Workspace/MemoirVerificationNov03/DeviceBuildCache-3.45.zip`. `unzip -tq` verified all compressed data before removal of the internal temporary copy. The signed `.xcarchive`, source commit and test results are preserved. To restore the optional cache, use `ditto -x -k` with that ZIP and `/tmp` as the destination. No user data or unrelated project cache was removed.

Submission status independently rechecked at 2026-11-03T16:54:41-06:00: `Waiting for Review`, one item submitted, release mode `MANUAL`.
