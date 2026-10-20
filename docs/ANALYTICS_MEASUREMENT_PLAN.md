# Memoir product measurement plan

Updated October 19, 2026. Engineering handoff for the current working tree; event availability in source does not establish released-build coverage or validated dashboard counts.

## Configuration and ownership

- Mixpanel project **3768856** is the intended destination. The previous app token targeted the wrong destination; the current analytics configuration was corrected during this work. Compare old and new populations before interpreting a discontinuity.
- RevenueCat project **25cadd3a** now has an ACTIVE Mixpanel integration, default `rc_*` event names, and gross revenue reporting. Its sandbox token is blank, so sandbox purchase events are not forwarded. Its secret is blank; delayed refunds older than five days are not covered yet. These are configuration observations supplied by the root implementation session, not a demonstrated production transaction test.
- `ProductAnalytics` supplies `environment`, `schema_version`, `session_id`, and `account_type`; Firebase identity is used for the product stream. Verify that RevenueCat lifecycle events resolve to the same Mixpanel person after anonymous login, account linking, logout, restore, and account switching.
- App-side changes require a new released binary. Do not treat existing installations as instrumented until their build is known. No backend deployment or app release is authorized by this plan.

## Acquisition

CalebMark owns external acquisition reporting. Keep campaign exposure, click, App Store download, and product activation in separate source systems until attribution supports a join. Do not infer a person-level funnel by dividing unrelated dashboard totals.

- Use `First Launch` for installation-first-open analysis and `App Launched` for launch diagnostics. `First Launch` uses local defaults: reinstall/new device can repeat it, and it is not a customer-first-ever flag.
- Apple AdServices collection is already enabled after RevenueCat configuration. Keep brand/category campaigns separate; unknown attribution stays unknown. Do not send raw attribution tokens to Mixpanel.
- Use attributed RevenueCat first paid outcomes for future acquisition economics. Active entitlement, trial, restore, and onboarding completion are not payments.
- Existing emails/customer counts are source-specific populations, not unique installs or an eligible activation denominator. Do not upload raw emails to bridge datasets. Customer aliases, opt-in Apple usage, existing customers, web billing, dates, and environment change the scope.

## Activation

Primary product activation is the first experienced personalized result, independently of payment. Build a unique-person ordered funnel over a stated seven-day window:

1. `Onboarding Started`.
2. `Onboarding Memory Saved Locally`.
3. `Onboarding Memory Synced`.
4. `Onboarding Preview Image Ready`.
5. `Onboarding Personalized Reveal Viewed`.
6. `Onboarding Completed` as a separate flow-completion outcome.

Report generated-to-viewed conversion as unique eligible people with the reveal after ready divided by unique eligible people with ready. Also report matched-flow diagnostics. `Onboarding Personalized Reveal Viewed` requires navigation to reveal with the preview image and audio ready; it does not assert that the person read the whole page or listened to the full recording. `Onboarding Completed` follows paywall dismissal, not successful purchase.

`flow_id` is currently view-instance state, not persisted across app termination or cross-device resume. `generation_attempt` increases for retries, and the reveal guard resets for a new generation attempt. Do not count every ready/cached/reveal event as a new activated person. Use first qualifying milestone per identity for activation; use flow and attempt only for within-instance debugging. Cross-restart exact generation joins remain a gap.

## Onboarding reliability and friction

Use these implemented events with their bounded context:

- Navigation: `Onboarding Step Viewed`, `Onboarding Step Exited`, `Onboarding Action`, `Onboarding Tour Finished`, `Onboarding Audience Selected`.
- Lifecycle: `Onboarding Backgrounded`, `Onboarding Foregrounded`.
- Input: `Input Started`, `Input Completed`; only field category, duration, and character count. No keystrokes, typed values, names, transcripts, prompts, audio, images, or URLs.
- Recording: `Onboarding Recording Started`, `Onboarding Recording Stopped`, `Onboarding Recording Failed`.
- Sample: `Onboarding Sample Playback Started`, `Onboarding Sample Playback Stopped`; sample playback is not personalized activation.
- Generation: `Onboarding Generation Started`, `Onboarding Preview Image Ready`, `Onboarding Preview Failed`, plus local-save/sync milestones above.
- Preparation/photo: `Onboarding Preparation Failed`, `Onboarding Photo Added`.

Review step-to-next-step unique-person conversion, time distributions, error counts, retries, background/resume, and generated-to-reveal delay. Separate cached ready results from fresh generation latency. Generation-start is a client attempt and does not prove backend admission. No later event can mean app closure, offline delivery, process death, another device, uninstrumented build, or instrumentation failure; it does not prove confusion. Diagnose with multiple signals and a reproduced flow before changing a screen.

## Payments

The primary paywall exposure denominator is `Paywall Viewed` after preparation, once per `presentation_id`. `Onboarding Paywall Viewed` is the onboarding sheet context; do not sum it with `Paywall Viewed` as two impressions.

- Purchase UX: `Subscription Purchase Started`, `Subscription Purchase Cancelled`, `Subscription Purchase Failed`.
- Restore UX: `Subscription Restore Started`, `Subscription Restore Failed`.
- Entitlement verification: `Subscription Activation Started`, `Subscription Activation Succeeded`, `Subscription Activation Failed`, with `purchase_origin` distinguishing purchase and restore.
- Other outcomes: `Paywall Preparation Failed`, `Paywall Dismissed`, with bounded dismissal reasons.

Activation succeeded means usable entitlement, including possible trial or restored entitlement. It is not a paid conversion. Use the ACTIVE RevenueCat integration's verified `rc_*` events for trial, initial paid charge, renewal, expiration and refund reporting. Inventory exact delivered provider event names and payloads in Mixpanel before constructing saved lifecycle reports; do not invent client replacements or infer charges from callbacks. Gross revenue excludes neither store commission nor all operating costs and is not profit.

Measure unique people who start a trial or make a first paid charge after a paywall impression, and mature trial-to-paid cohorts. Deduplicate provider lifecycle events by their stable provider identity/transaction. Define first paid once per customer for subscription acquisition; retain renewal transaction counts separately. Resolve the delayed-refund secret/configuration gap before trusting net revenue or refund-adjusted conversion.

## Creation and retention

- Foreground use: `Session Started`, `Session Ended`, `Tab Viewed`. A background-to-active transition starts a new session; inactive interruptions alone do not. Session end is not guaranteed on process termination.
- Creation: `Started Recording`, `Saved Memory`, `Memory Save Failed`. `Saved Memory` currently represents a successful local save, not confirmed cloud synchronization for every capture route.
- Consumption: `Viewed Memory`, `Memory Playback Requested`, `Memory Playback Started`, `Memory Playback Completed`, `Memory Playback Failed`. Remote request and actual local playback start have different semantics; do not combine them as proof of listening.
- Sharing: `Memory Share Sheet Presented`, `Memory Shared`, `Memory Share Cancelled`, `Memory Share Failed`. Share completion reflects the platform callback, not recipient readership.
- Books: `Book Generation Requested`, `Book Illustrations Completed`, `Book Generation Completed`, `Book Generation Cancelled`, `Book Generation Failed`.
- Identity: `Authentication Started`, `Authentication Succeeded`, `Authentication Failed`, `Signed Out`.

Report app-return retention separately from meaningful-use retention. Anchor cohorts on first personalized reveal; count return-day `Saved Memory`, `Viewed Memory`, completed playback, or book completion as explicit activity definitions. Show D1, D7 and weekly meaningful return with mature denominators, and second-memory creation within seven days. Memoir creation may be episodic; session count alone is not success.

Book completion is client finalization/readiness, can be observed again on resume, and currently lacks a stable analytics generation ID. Use unique people for current conversion reports; do not equate event count with unique books. A distinct full-book actually-viewed event remains unimplemented.

## Cohorts and interpretation

- Production product reports filter `environment=production`; explicitly exclude development, tests, sandbox and known internal QA identities. RevenueCat sandbox events are currently disabled, so a sandbox end-to-end test requires deliberate separate configuration rather than expecting production lifecycle delivery.
- Keep calendar timezone, app/build coverage, attribution window, cohort anchor, identity rules and observation window fixed. Show numerator and denominator, not only percentages.
- D7 cohorts need seven full days; trial-to-paid requires the trial duration plus reporting allowance. Do not label an immature cohort's zero paid outcomes as final failure.
- Historical reference only: dashboards inspected October 18, 2026 showed September RC 12 trial starts/389 new customers and 6 paid within 30 days/389; six conversions/12 trials was a tiny, not fully mature sample. Apple September 21–27 D1 retention was 10% with unknown opt-in cohort size. These are different populations, not a baseline for the newly corrected Mixpanel stream.

## Remaining backend and commerce work

Priority 1: validate live event receipt and identity joins with a released instrumented build; confirm provider `rc_*` payload semantics and refund configuration. Record synthetic versus production evidence separately. Audit remaining capture routes so `Saved Memory` does not silently represent only one workflow.

Priority 2: implement a transactional analytics outbox for authoritative generation milestones. Existing `onboardingPreviewJobs` already distinguishes admission, generating, cached image-ready, attempts and failure; storybook admission distinguishes accepted/replay/rejected and the worker distinguishes illustrations from finished client books. No backend Mixpanel transport exists today. Emit accepted/terminal milestones once per stable analytics-only job identity, with safe failure enums, counts and durations. Transactional outbox plus stable delivery IDs must survive worker retries and transport outages without storing private generated content in analytics.

Priority 3: add stable job correlation to client ready/view events and persist first activation if cross-device exactness is needed. Avoid using raw memory/profile IDs. Keep attempt events distinct from logical output milestones, and test replay, resume, cached success, partial failure and account switching.

Priority 4: instrument physical commerce separately. Existing Stripe signed webhooks and common paid-cart/single-book commit functions verify payment and deduplicate deterministic orders; reconciliation can also commit orders. Emit paid events from the common committed state/outbox, not only the webhook or app return URL. One payment revenue event per checkout, separate line-order fulfillment events, verified refund/dispute and signed Lulu lifecycle events. Exclude test orders. Checkout started, paid, fulfillment hold, submitted, shipped/delivered and refunded must stay distinct. These Mixpanel print-order events are not implemented.

## Verification before using reports

- Verify actual project receipt, allowed properties, production versus test labeling, anonymous-to-account joins and account-switch isolation.
- Exercise fresh and cached preview, generation failure/retry, background/restart, local-save failure, restore, purchase cancellation and entitlement failure using safe test environments.
- Confirm one paywall impression per presentation, retries remain visible, and no client event asserts revenue.
- Record build/test results and physical-device delivery evidence; source inspection alone cannot certify end-to-end telemetry.
