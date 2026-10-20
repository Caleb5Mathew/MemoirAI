# Understanding Memoir events

The catalog describes all **73 app events**, organized into **13 product areas**, using the current source callsites. Event names are unchanged so existing reports keep working.

- `event-catalog.json` contains each event's category, plain-language description, interpretation limits, and source locations.
- `event-catalog.csv` contains the same descriptions in a spreadsheet-friendly format. It is a handoff format, not a claim that Mixpanel supports a direct CSV import.
- In Mixpanel Lexicon, use `description` as the event description and `category` as a tag. This describes existing events without changing their identity.
- New app events receive a trusted `event_category` property for filtering and breakdowns. This requires shipping the updated binary; it does not backfill historical events. Unknown events receive `Uncategorized` so missing catalog entries remain visible.

## Live Mixpanel status

On October 20, 2026, the main implementation session verified the import of all 69 descriptions and their category tags into Mixpanel Lexicon, project 3768856. The Production & QA board (11597434) also has a saved four-step onboarding activation funnel with a seven-day conversion window and 30-day report range. See the measurement plan for exact filters and interpretation. This is verified configuration, not proof of populated customer conversion results or purchase attribution. Saved report 93516004 adds day-by-day return-to-memory-detail retention (repeat reveals may re-enter cohorts). Internal QA report 93494994 now uses built-in All Events with `traffic_type=internal`; its nonempty displayed average is event volume, not people or revenue.

## Product areas

1. App lifecycle: launches and foreground sessions.
2. Account access: sign-in, account linking, and sign-out.
3. Navigation and input: named screens, tabs, controls, and edit summaries.
4. Onboarding navigation: steps, audience choices, interruptions, and flow completion.
5. Onboarding capture: voice recording and photo selection.
6. Onboarding generation: saving, synchronization, preview generation, and personalized reveal.
7. Onboarding sample tour: Alex's demo playback; keep separate from personal activation.
8. Subscriptions: paywall, purchase/restore attempts, and entitlement activation.
9. Memory creation: regular recording and local memory saving.
10. Memory reading and listening: detail views and audio playback.
11. Memory sharing: share-sheet and platform completion callbacks.
12. Memory enhancement: guided character-detail extraction and persistence attempts.
13. Book creation: full-book generation and finalization.

## Reading the numbers correctly

`Onboarding Personalized Reveal Viewed` is the personalized-value milestone. `Onboarding Completed` means the flow finished after paywall dismissal. `Subscription Activation Succeeded` means an entitlement is usable, including trials and restores. None of these proves payment. RevenueCat's delivered lifecycle events need their own verified catalog and identity checks before paid-conversion reporting.

`Saved Memory` confirms local persistence in the regular recording flow. `Onboarding Memory Synced` confirms the separate onboarding sync stage. `Book Generation Completed` is a client readiness observation and can repeat on resume; event count is not unique books.

`Memory Enhancement Auto Saved` now requires successful local persistence. `Memory Enhancement Save Failed` keeps failed attempts separate, and the screen offers retry instead of claiming success. Historical builds before this fix could emit the success event after a caught save error; historical success counts therefore need that caveat.

Use production + external + physical-device filters for customer reporting. Internal/simulator data remains useful for QA but is not a customer funnel. Descriptions and categories do not send names, memoir text, images, audio, or individual keystrokes.

## Foreground dwell and bounded diagnostics

The latest source adds four events beyond the 69 previously imported live: `Screen Time Recorded`, `Recording Start Failed`, `Memory Transcription Retry Queued`, and `Memory Transcription Retry Failed`. Their Lexicon import and updated-binary delivery are separate verification steps; do not assume they are already live.

Screen timing covers the main navigation and onboarding steps, with 20 named native destinations. Instrumented sheets suspend the underlying screen and restore its timer on dismissal. Inactive/background time is excluded, repeated appearances are deduplicated per view instance, and identity changes split timing segments. Sum `duration_ms` by `screen` to measure dwell; segment count is not visits. Longer dwell can mean interest, difficulty, or distraction; it is not automatically positive engagement.

Known limits: system camera/photo/share pickers and hosted checkout may remain attributed to their parent while the app stays active. Force quit/crash can lose the unfinished segment. Existing onboarding `step_duration_ms` is wall-clock step duration and must not be silently mixed with foreground dwell. Screen views and timing do not prove reading completion, payment, or crash detection.

Existing `UI Action` now identifies `retry_generation`, `retry_paywall`, and `retry_transcription` using bounded screen labels. Recording diagnostics use only `auth_unavailable`, `recorder_start_rejected`, or `recorder_creation_failed`; no error messages, file paths, memoir text, names, photos, audio, or individual keystrokes are collected.
