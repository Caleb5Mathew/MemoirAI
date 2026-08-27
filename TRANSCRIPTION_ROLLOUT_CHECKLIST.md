# Production Transcription Rollout

## Implemented safeguards

- New recordings use mono M4A/AAC at 48 kbps and stop at 60 minutes, keeping expected audio below the provider's 25 MiB file limit.
- Storage rules restrict owner M4A uploads to `audio/mp4`, non-empty files, and 25 MiB.
- The callable validates Storage metadata before downloading, pins the object generation, and validates the downloaded buffer before reserving quota.
- Per-memory leases deduplicate concurrent requests. Completion/failure writes only apply to the active job and audio revision.
- Ordinary iOS sync preserves server-owned raw/status/model/version fields and skips unchanged audio uploads.
- Pending retries are scoped to the signed-in Firebase user and retain the profile glossary.
- Memory deletion cancels local pending sync and removes the Firestore document plus M4A/CAF Storage objects.
- Re-recording keeps the previous recording until the replacement has saved successfully.
- Story generation stops before creating a job when required audio is not transcribed.
- The microphone disclosure now states that audio is uploaded and processed by the transcription provider.
- Cloud Functions target Node.js 22 rather than the decommissioning Node.js 20 runtime.

## Required product decisions

- Update the public privacy policy: recordings are uploaded to Firebase Storage and processed by OpenAI to create a transcript.
- Decide the default transcription language and add language selection before supporting non-English recordings.
- Confirm the retention policy for raw audio and raw transcripts.
- Decide whether the current microphone disclosure is sufficient consent or whether first-recording opt-in must be explicit.

## Required production actions

- [x] Deployed `transcribeMemoryAudio` to `memoirai-7db06` with `OPENAI_API_KEY` secret version 1 on August 27, 2026.
- [x] Deployed the updated Storage rules before the callable on August 27, 2026.
- [x] Verified an authenticated production M4A upload, OpenAI transcription, completed Firestore state, and cleanup using a temporary Firebase user.
- [x] Verified production rejects wrong-content-type uploads, cross-user Firestore/Storage access, unauthenticated callable requests, and malformed callable payloads.
- [x] Built and launched the compiled app on an iOS 26.5 simulator after deployment.
- Deploy the Core Data/CloudKit schema changes from an Xcode development build before releasing the app.
- Add the audio-processing disclosure to the App Store privacy information.
- Burn in Firebase App Check metrics, confirm the shipped provider matches Firebase registration, then set `ENFORCE_APP_CHECK=true`.
- Add spend/rate alerts and a project-wide transcription budget breaker. The per-account daily limit is not sufficient against multi-account abuse.
- Upgrade `firebase-functions` from 7.0.5 to the current SDK in a separate dependency PR and dry-run every callable; the Firebase CLI currently warns that it is outdated.
- Record and approve a consented evaluation set covering quiet/noisy rooms, older voices, accents, and important family/place names.
- Enable the feature for internal users first and measure transcript correction and retry rates before a full rollout.

## Required automated validation

- Firebase Emulator callable tests: unauthenticated, owner success, missing/wrong path, empty/oversize/wrong content type, quota preflight ordering, duplicate request, response-loss retry, re-record race, delete race, and provider error mapping.
- Firebase rules tests: reject non-owner audio; reject oversized, empty, wrong-type, and malformed-path M4A; retain allowed legacy CAF behavior.
- Two-device sync tests: stale queued/processing state cannot replace completed raw text; empty and non-empty edits survive retries; a newer re-record always wins.
- Core Data concurrency tests with `-com.apple.CoreData.ConcurrencyDebug 1` for both creation flows and re-recording.
- Hydration tests: existing-row completion reconciliation, edited-text precedence, account switching, failed audio download, and failed local file write without deleting cloud audio.
- Deletion tests: pending and in-flight work cannot recreate the memory; Firestore plus M4A/CAF objects are removed.

## Required device validation

- Record and replay 1-second, silent, interrupted, Bluetooth, 10-minute, 30-minute, and 60-minute samples on a real device.
- Confirm each file is valid M4A/AAC, remains below 25 MiB, uploads as `audio/mp4`, and plays after relaunch.
- Validate pause/resume and copied checkpoint files. Copying an actively written M4A may produce an unfinalized container and must not be treated as recovered audio until proven playable.
- Validate the compiled missing-file playback fallback. The existing fallback lives in `CharacterDetails.swift`; the newer `MemoryEntry+Playback.swift` implementation is excluded from target membership.
- Test queued, processing, completed, failed, retry, and legacy re-record UI at AX5 Dynamic Type, iPhone SE width, VoiceOver, and RTL.

## Account-side blockers

- CloudKit production schema deployment requires a CloudKit Console session or a `cktool` management token for team `SNG8SZK5TY` and container `iCloud.com.Buildr.MemoirAI`.
- App Store privacy answers require a signed-in App Store Connect session. The current submission only lists precise location and must also disclose linked audio data, transcript/user content, identifiers, purchases, and the purposes actually used by the app.
- Firebase App Check enforcement stays off during burn-in so installed versions that do not send a valid token are not broken.

## Release acceptance criteria

- A new M4A recording uploads, reaches `completed`, and saves a raw transcript.
- A user edit is preserved when a transcript is retried.
- A user can retry a failed upload/transcription without re-recording.
- Existing CAF recordings remain playable and show a clear re-record message until a migration path is released.
- App termination at upload, provider request, and completion-write boundaries recovers without duplicate provider work or transcript regression.
- Deleting a memory removes its cloud audio and it stays deleted after foreground retry.
- Story generation never starts with an empty transcript for a recorded memory.
