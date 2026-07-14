# Storybook pipeline — living knowledge

Update this file at the end of each test cycle (after grading images + audit trail).

## Confirmed working (Cycle 1 — shipped)

- **Failed-job dismissal:** Worker marks prior `failed` jobs for same profile as `dismissedFailed` when a new job starts. Client `pickActiveStorybookCloudJob` skips `dismissedFailed` and only surfaces `failed` when no newer superseding job exists (`complete`, in-flight, etc.).
- **Extraction anti-hallucination (new runs only):** iOS `extractStructuredDetails` / `parseSceneSpec` forbid inferring gender/ethnicity/age/hair/clothes when not stated.
- **Card name normalization (partial):** Cloud + iOS rewrite `I`/`Me`/… to display label; `Mother` + `wife` → `Mother (the narrator's wife)`.
- **Per-page age override:** Cloud `narratorAgeOverrideForPage` + `AGE OVERRIDE FOR THIS PAGE` under headshot reference when card age or explicit text age exists.
- **Anti-bleed (non-family):** PEOPLE-RENDER LOCK told model empty ethnicity ≠ narrator heritage (pre–family_match).
- **Anti-clone:** Global PEOPLE-RENDER rule for sparse appearance rows + headshot face reuse.
- **Scene pronoun discipline (v1):** `extractVisualScene` rule 10 — empty listed gender → no invented he/she; use name or they.

## Confirmed bugs fixed in Cycle 2 (this PR)

- **E1:** `normalizeCardDisplayNames` now rewrites **any** card whose `relationshipToNarrator` contains `memoir narrator` (fixes `Mom` + memoir narrator split in Thanksgiving scene).
- **E2:** `extractVisualScene` rules 11–12 — roster labels override source kin phrases; stricter empty-narrator-gender rule.
- **E3:** AGE OVERRIDE extended: re-age face only; do not change ethnicity/gender/bone structure beyond age-appropriate development.
- **E4 (family_match):** `isFamilyOfNarrator` + soft `profileEthnicity` fallback for family rows with empty ethnicity; bare `in-laws` excluded; PEOPLE-RENDER ethnicity rules updated (family vs non-family).
- **E5:** When headshot attached, PEOPLE-RENDER LOCK prepends permanent headshot identity anchor.
- **E6:** `stripLikelyHallucinatedNarratorGender` — if job `gender` empty and memory has no explicit narrator-gender cue, strip narrator-card `gender` (stale extraction hallucination); logs `storybook.narratorGenderHeuristicStripped`.
- **explicitAge:** `senior year` / `junior year` / `sophomore year` / `freshman year` heuristics for Memory B–style tests.

### Test infra (Cycle 2)

- **`BookVersionPersistOrderingTests`:** `@Suite(.serialized)` — both tests mutate the same `UserDefaults.standard` key as production; parallel Swift Testing caused rare flakes.

## Known limitations / stale data

- **Pre-deploy character cards** may still contain hallucinated fields (e.g. `gender:"female"` on Fishing). Cycle 2 **E6** strips narrator gender at **cloud job time** when safe; re-enhancing the memory on iOS still produces the cleanest long-term data.
- **family_match V1** does not recurse spouse-side families (e.g. Maria’s parents with `in-laws` stay non-inherited by design; explicit spouse ethnicity still wins).

## Untested edge cases (queue)

- Recursive family_match from non-narrator anchors (spouse’s parents inherit spouse heritage).
- Very large rosters (15+) + anti-clone.
- Narrator `likelyAbsent` + headshot attach policy edge cases.
- Mixed-language memories.
- Memories where profile ethnicity conflicts with explicit narrator-card ethnicity.

## Test memory roster (Cycle 2 probe set — user-created)

| ID | Title | What it probes |
|----|-------|----------------|
| A | Wedding Day, September 1992 | Multi-heritage + family_match + headshot anchor |
| B | First Start at Quarterback | Senior year → 17, peers anti-clone, jersey #12, empty genders |
| C | The Magnolia Tree | Reflective / low-action + family + never-met grandparent |

Full scripted text and card fields: see project plan **Storybook Test Cycle 2** (do not duplicate here unless expanded).

## QA grading sheet (per image)

1. Narrator face vs headshot identity (same / drift / wrong).
2. Narrator age vs AGE OVERRIDE (match / slight / wrong).
3. Narrator ethnicity vs headshot + cards (match / drift / wrong).
4. Narrator gender presentation vs headshot, not inferred from bad card (match / inferred / conflict).
5. Family ethnicity (family_match) (match / mixed / wrong).
6. Non-family ethnicity independence (varied / cloned / bled).
7. Anti-clone (duplicate faces? which pair).
8. Scene paragraph uses roster labels not source kin words (yes / no — cite).
9. Key props (A leaves, B #12, C blooms) (present / absent).
10. Scene beat specificity vs generic table shot (specific / generic / wrong).

## Audit trail

- iOS: filter device logs for `[StorybookGen]` and cloud job audit block.
- Cloud: Firebase / Cloud Logging for `storybook.*`, `storybook.assembledPreview`, `storybook.narratorGenderHeuristicStripped`.
