# Notes bug audit — November 5, 2026

Status: completed. Fixes verified, targeted backend deployed, and version 3.45 build 2026.11.5 submitted to App Review. App Store Connect confirmed **Waiting for Review** on November 5, 2026 at approximately 09:49 CST.

Verified source: `abc9ff2`; backend source: `f7a3527`. Candidate: 3.45 (2026.11.05).

Branch: `fix/notes-audit-2026-11-05`, based on the submitted 3.45 source (`cfe55ff`). The original Documents working tree contains separate unfinished changes and is preserved.

## Reported problems and changes

- **Profile resets after restart:** restore the selected profile by account-scoped UUID before persisting any fallback index. Delayed cloud hydration cannot overwrite a newer selection; a transient failure preserves an unresolved remote selection for retry.
- **Wrong person's memories or books:** reject stale account/profile results and listeners. Validate a routed job's actual profile before attaching it, refresh lists on selection changes, and query all books for the selected profile rather than filtering only the account's newest 80 rows.
- **Profile photo:** use the selected profile's photo in the Home control, with the existing fallback when none exists.
- **Inconsistent progress:** calculate Home progress using the same deduplicated prompt slots and personalized/legacy prompt matching as chapter progress. This measures completed prompts, not simply chapters with at least one memory.
- **Your Book stops opening:** use a single typed navigation path and clear stale routes when changing profile. Repeated taps and returning from the chapter journey must leave the book reachable.
- **Nine-story limit:** raise the client/server ceiling to 40 eligible stories, including written and chapterless memories. The setting describes stories, not physical printed pages; allowance and actual eligible count still constrain the choice.
- **Generation settings clutter:** collapse secondary account/help controls and omit Print Orders from the generation step. Account settings retain order access.
- **Image counter:** remove the redundant image allowance fraction from the book header.
- **Stuck transcription:** distinguish upload, authentication, rate limit, daily capacity, network, timeout, and invalid recording failures. Expired processing states permit retry; remote M4A sync preserves the canonical server transcript.
- **Save & Generate crash:** guard reader snapshots/editor indices and reject cross-profile generation callbacks. No device crash report was recovered, so the original crash cause is not proven. Reader previews now decode bounded thumbnails while retaining original image bytes for print and editing. A 40-image regression measures decoded preview memory below 210 MiB; print retains the original 3300×2550 images. This is not a whole-process memory guarantee.
- **Long generation interruptions:** resume in bounded server batches with persisted results and reservation, instead of retrying or charging completed stories again. Deadline-limited retries defer unfinished stories; bounded partial results must remain usable.
- **Diagnostics:** emit typed, privacy-safe transcription/generation failure reasons without recording names, recordings, or transcript text.

## Verification

- Final iOS verification passed: 112 XCTest unit tests and 513 Swift Testing cases (625 total), plus three navigation UI regressions. Six additional onboarding/name UI tests passed in the preceding run. The final navigation run corrected failures from the preceding run; those earlier failures are not counted as passes.
- Navigation tests cover cold-launch profile restoration, returning from chapters, and four repeated double-tap/back book navigation cycles. Retained screenshots show the book screen remains reachable.
- Testing uncovered an actual chapter crash caused by an ambiguous Core Data entity in multiple loaded models. Context-resolved fetch requests fix both chapter and recording views; a two-store regression verifies isolation.
- Full backend suite and real Firestore emulator admission/refund security regression passed. Forty-story continuation uses mocked providers with real orchestration; no paid production generation, payment, or physical order was placed.
- Independent reviews corrected profile resume, job identity, worker retry deadlines, partial delivery, print image preservation, and allowance receipt readiness. Final receipt review found no remaining blocker.
- Release configuration gates and diff checks passed. The signed device archive succeeded; bundle identity, version/build, code signature, and matching app/dSYM UUID were verified.
- The four storybook functions and narrow Firestore rule change deployed successfully. All four functions report ACTIVE. An unauthenticated admission call returned HTTP 401 as expected.
- Compatible transitive dependency updates reduced the production audit from six affected packages to one. Remaining Nodemailer advisories are not represented as resolved; a major mail migration is outside this release.

Artifacts: `/Volumes/Memoir Video Workspace/MemoirNotesFixVerificationNov05`. Final unit/navigation result: `FinalRegression-7.xcresult`; six additional passing UI cases: `FinalRegression-4.xcresult`. Final backend log: `/tmp/memoir-backend-final-live-preserved-nov05.log`.

## Deployment and rollback

Only `createStorybookJob`, `processStorybookJob`, `continueStorybookJob`, `settleStorybookJobReservation`, and the admission rule guard were deployed. Previously deployed function source ZIPs, metadata, and rules are preserved in `BackendRollback` beneath the verification directory. No order/email/payment functions changed.

Old reproducible OurStory build/module caches were ZIP-backed-up and verified before removal; old completed Memoir test results were moved with hashes verified and original paths retained as symlinks. Backups are in `CacheBackups` and `PreviousTestResults` beneath the verification directory. User source/data and protected USB folders were untouched. Restore cache ZIPs with `ditto -x -k ZIP /tmp/ourstory-audit-dd-2`.

## App Store status

The previously approved 3.45 build 2026.11.3 was canceled and replaced with 2026.11.5 (archive build string 2026.11.05). App Store Connect confirmed **Waiting for Review** and **1 Item Submitted** at approximately 09:49 CST on November 5. New build identifier: `c1db6fd5-ec1c-4cf3-ab04-ae6364ffc2ee`.

Existing review credentials/contact details and manual release were preserved. Version 3.44 remains public; the new version is not live yet. Xcode reported missing dSYMs for several precompiled dependencies, but the app's own dSYM UUID matches and Apple accepted and processed the upload.

The signed archive is `Memoir-3.45-2026.11.05.xcarchive` beneath the verification directory. Upload log: `/tmp/memoir-notes-appstore-upload.log`. The temporarily reused prior-release worktree was restored to its original branch after upload; the original dirty Documents worktree was preserved. The restored temporary device cache was removed after upload; its original verified ZIP and both release archives remain available.


## Reproduce the Firestore security regression

The emulator test exercises real Firestore rules and transactions: legacy client edits remain allowed, client promotion to server admission is denied, refund provenance cannot be forged, callable admission succeeds, and a server-confirmed refund is applied exactly once. It uses a `demo-` project and refuses to run unless `FIRESTORE_EMULATOR_HOST` points to localhost.

Prerequisites: Node 22 and Java 21 or newer. On this Mac, Java 21 is available through Homebrew at `$(brew --prefix openjdk@21)/bin`; put that directory on PATH before running Firebase CLI. Install the functions dependencies with `npm --prefix functions ci`.

Run from the repository root:

```sh
rules_sdk_dir="$(mktemp -d)"
npm install --prefix "$rules_sdk_dir" --no-save @firebase/rules-unit-testing@5.0.2 firebase@12.19.0
export NODE_PATH="$rules_sdk_dir/node_modules"
cat > "$rules_sdk_dir/firebase.json" <<'JSON'
{"emulators":{"firestore":{"host":"127.0.0.1","port":8188},"hub":{"host":"127.0.0.1","port":4408},"logging":{"host":"127.0.0.1","port":4508},"ui":{"enabled":false},"singleProjectMode":true}}
JSON
npx --yes firebase-tools@15.8.0 emulators:exec --only firestore --project demo-memoir-security --config "$rules_sdk_dir/firebase.json" "node --test functions/storybookAdmissionRules.test.js"
```

The pinned test SDK versions are isolated from production dependencies. Firebase CLI starts and stops the emulator for this command; no live project credentials or production writes are needed. Permission-denied messages for the deliberately forbidden operations are expected. The test passed against Firestore emulator 1.20.2 using Java 21 on November 5.


## Comparison against deployed function source

The four downloaded production source archives were compared before deployment. The generation worker keeps the deployed `gemini-3-pro-image-preview` model; an unrelated inherited model rename was removed. The callable retains its deployed RevenueCat verification path; an inherited developer-quota bypass was not enabled by this release. The 200-candidate input cap is intentional so a book can select up to 40 stories from a larger library, and preferring a narrator's edited transcript is part of the transcription correctness fix.

The active worker's account-deletion guards, retry deadline helpers, privacy logging, failure sanitization, and admin authorization helper match the deployed versions. The formerly inert continuation trigger now uses the same checked worker and guards. No order, payment fulfillment, email, or unrelated function is included in the targeted deployment.
