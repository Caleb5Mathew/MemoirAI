# Onboarding reliability and first-story refinement

Status: local release candidate; not uploaded or submitted for review.

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
- Device archive/signing: running for version 3.45, build 2026.11.03 (command-line overrides; committed pricing and project settings retained).
- App Store upload/review submission: not performed.

Known limits: browser automation remains unavailable for inspecting the single historical failed-preview profile or saving Mixpanel reports. Simulator tests do not establish a real App Store purchase. No conversion uplift is claimed before rollout.
