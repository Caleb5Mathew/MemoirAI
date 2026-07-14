/**
 * Server-side ports of StoryPageViewModel + GeminiImageService storybook AI helpers.
 * Prompts mirror Swift sources for consistent outputs.
 */

const OpenAI = require("openai");
const path = require("path");
const fs = require("fs");
const admin = require("firebase-admin");
const crypto = require("crypto");

const GEMINI_IMAGE_MODEL = "gemini-3-pro-image-preview";
const GEMINI_TEXT_MODEL = "gemini-2.5-flash";
const OPENAI_TEXT_MODEL = "gpt-5-mini";

function storageBucket() {
  return admin.storage().bucket();
}

/** Shared Storage upload used by both the storybook worker and the aiProxy callables. */
async function uploadPngWithDownloadURL(storagePath, buffer) {
  const token = crypto.randomUUID();
  const f = storageBucket().file(storagePath);
  await f.save(buffer, {
    resumable: false,
    metadata: {
      contentType: "image/png",
      metadata: { firebaseStorageDownloadTokens: token }
    }
  });
  const enc = encodeURIComponent(storagePath);
  const url = `https://firebasestorage.googleapis.com/v0/b/${storageBucket().name}/o/${enc}?alt=media&token=${token}`;
  return { storagePath, url };
}

const BOOK_STYLES_PATH = path.join(__dirname, "style", "bookStyles.json");
const BOOK_STYLES = JSON.parse(fs.readFileSync(BOOK_STYLES_PATH, "utf8"));

/** iOS persists `ArtStyle.rawValue` ("Kid's Book", "Realistic", …); worker expects camelCase keys. */
const ART_STYLE_ALIASES = {
  kidsbook: "kidsBook",
  "kids book": "kidsBook",
  "kid's book": "kidsBook",
  kids: "kidsBook",
  realistic: "realistic",
  real: "realistic",
  comic: "comic",
  "comic book": "comic",
  custom: "custom"
};

function normalizeArtStyleKey(raw) {
  const k = String(raw || "")
    .trim()
    .toLowerCase();
  if (!k) return "kidsBook";
  if (ART_STYLE_ALIASES[k]) return ART_STYLE_ALIASES[k];
  if (k.startsWith("kid")) return "kidsBook";
  if (k.startsWith("real")) return "realistic";
  if (k.startsWith("comic")) return "comic";
  return "custom";
}

function artStyleMemoryIllustrationStyleDescription(rawArtStyle, customText) {
  const artStyle = normalizeArtStyleKey(rawArtStyle);
  const trimmedCustom = String(customText || "").trim();
  switch (artStyle) {
    case "kidsBook":
      return BOOK_STYLES.kidsBook;
    case "realistic":
      return BOOK_STYLES.realistic;
    case "comic":
      return BOOK_STYLES.comic;
    case "custom":
    default: {
      const tpl = BOOK_STYLES.customTemplate || "Custom style described as: '{{custom}}'. Strictly follow this style direction.";
      return tpl.replace("{{custom}}", trimmedCustom || "an undefined style");
    }
  }
}

const COVER_STYLE_BINDING =
  "BINDING INSTRUCTION: Render strictly according to VISUAL STYLE above (medium, linework, color, and lighting). Do not substitute a different illustration genre or default to soft watercolor unless VISUAL STYLE specifies watercolor children's book.";

function styleReferencePromptHint(rawArtStyle, styleReferencePreset) {
  const artStyle = normalizeArtStyleKey(rawArtStyle);
  if (artStyle !== "kidsBook") return null;
  const preset = styleReferencePreset || "normal";
  switch (preset) {
    case "normal":
      return `STYLE REFERENCE HINT (Normal): A style reference image is attached. Keep the same soft watercolor children's-book vibe and hand-drawn warmth as the reference. Preserve scene details and composition freedom from the memory, but keep rendering style consistent across pages.`;
    case "ref1":
      return `STYLE REFERENCE HINT (Ref1): A style reference image is attached. Match its hand-drawn watercolor children's-book vibe: soft pencil/ink lines, gentle paint texture, light paper feel, and warm natural palette. Keep scene details and composition creative, but keep rendering consistent with the reference across pages.
Little laughs in daylight glow, soft brushstrokes in a gentle flow.
Keep it warm and storybook sweet, with hand-drawn charm in every beat.
Avoid anime, vector-clean, cel-shaded, or glossy digital-cartoon rendering.`;
    case "ref2":
      return `STYLE REFERENCE HINT (Ref2): A style reference image is attached. Keep the same playful hand-drawn children's-book feel, simple readable forms, and consistent page-to-page rendering vibe. Preserve scene/action details from the memory and allow natural composition variation page to page.`;
    default:
      return null;
  }
}

function parseCharacterDetails(raw) {
  if (!raw || typeof raw !== "string") return null;
  try {
    const o = JSON.parse(raw);
    if (o && Array.isArray(o.characters)) return o;
  } catch (_) {
    /* ignore */
  }
  return null;
}

function stringifyCharacterDetails(details) {
  try {
    return JSON.stringify(details || { characters: [] });
  } catch (_) {
    return '{"characters":[]}';
  }
}

function escapeRegex(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Collapse long comma-separated proper-name runs so the image model does not echo them as captions.
 * Matches 3+ capitalized tokens separated by commas (e.g. "Ben, Caleb, Robbie, Zach, Katie").
 */
function collapseCommaSeparatedNameLists(text) {
  let s = String(text || "");
  const re = /(?:\b[A-Z][a-z]{1,25}\b)(?:\s*,\s*\b[A-Z][a-z]{1,25}\b){2,}/g;
  s = s.replace(re, "the group of friends");
  return s;
}

/** Memory context: collapse name lists + cap to keep prompt focused on context. */
function sanitizeMemoryContextForPrompt(text) {
  return collapseCommaSeparatedNameLists(String(text || "").trim()).slice(0, 600);
}

/** Profile display names that read as roles/relationships — must not drive visual age in image prompts. */
const RELATIONSHIP_STYLE_PROFILE_TOKENS = new Set([
  "grandparent",
  "grandma",
  "grandpa",
  "grandmother",
  "grandfather",
  "nana",
  "nan",
  "mom",
  "mum",
  "dad",
  "mother",
  "father",
  "mama",
  "papa",
  "mommy",
  "daddy",
  "aunt",
  "auntie",
  "uncle",
  "narrator"
]);

function isRelationshipStyleProfileName(name) {
  const lowerFull = String(name || "").trim().toLowerCase();
  if (lowerFull === "memoir narrator" || lowerFull === "the narrator" || lowerFull === "the storyteller") return true;
  const tok = normalizedFirstToken(name);
  if (!tok) return false;
  if (RELATIONSHIP_STYLE_PROFILE_TOKENS.has(tok)) return true;
  if (tok === "the" && lowerFull.includes("narrator")) return true;
  return false;
}

/** Display name for image-bound prompts (scene context + roster + interior canon lines). */
function imageNarratorDisplayName(job) {
  const raw = String(job?.profileName || "").trim();
  if (!raw) return "Narrator";
  return isRelationshipStyleProfileName(raw) ? "the memoir narrator" : raw;
}

/** Default visual-age hint when profile name is a relationship label and no face description. */
function narratorVisualAgeHintForImagePrompt(job) {
  if (!job || !isRelationshipStyleProfileName(job.profileName)) return "";
  if (String(job.faceDescription || "").trim()) return "";
  return "visual age: young adult (approx. late 20s — not elderly unless the memory text explicitly says so)";
}

/**
 * Maps free-text name or relationship strings to a coarse family-role bucket so we can detect
 * "Mother" + relationship "wife" style mismatches from extraction.
 */
function familyRoleKeyFromTextFragment(t) {
  const s = String(t || "")
    .toLowerCase()
    .trim();
  if (!s) return null;
  if (/\b(grandmother|grandma|granny|nana|nan)\b/.test(s)) return "grandmother";
  if (/\b(grandfather|grandpa)\b/.test(s)) return "grandfather";
  if (/\b(mother|mom|mum|mama|mommy)\b/.test(s)) return "mother";
  if (/\b(father|dad|daddy|papa|pop)\b/.test(s)) return "father";
  if (/\b(wife)\b/.test(s)) return "wife";
  if (/\b(husband)\b/.test(s)) return "husband";
  if (/\b(daughter)\b/.test(s)) return "daughter";
  if (/\b(son)\b/.test(s)) return "son";
  if (/\b(brother|bro)\b/.test(s)) return "brother";
  if (/\b(sister|sis)\b/.test(s)) return "sister";
  return null;
}

/** Defense in depth: normalize narrator placeholder names + role/relationship mismatches before roster/scene context. */
function normalizeCardDisplayNames(characters, job) {
  if (!characters || !characters.length) return characters;
  const display = imageNarratorDisplayName(job);
  const narratorAliases = new Set(["i", "me", "myself", "narrator", "the narrator", "the memoir narrator"]);
  return characters.map((c) => {
    const next = { ...c };
    const relRaw = String(next.relationshipToNarrator || "").trim();
    const relLower = relRaw.toLowerCase();
    if (relLower.includes("memoir narrator")) {
      next.name = display;
      return next;
    }
    const rawName = String(next.name || "").trim();
    const nameLower = rawName.toLowerCase();
    if (narratorAliases.has(nameLower)) {
      next.name = display;
      return next;
    }
    if (!relRaw) return next;
    const nameKey = familyRoleKeyFromTextFragment(rawName);
    const relKey = familyRoleKeyFromTextFragment(relRaw);
    if (nameKey && relKey && nameKey !== relKey) {
      next.name = `${rawName} (the narrator's ${relRaw})`;
    }
    return next;
  });
}

/** True when relationship string reads as narrator's kin (not friends/teammates). Bare "in-laws" = spouse's parents only — excluded. */
function isFamilyOfNarrator(rel) {
  const r = String(rel || "")
    .toLowerCase()
    .trim()
    .replace(/\s+/g, " ");
  if (!r) return false;
  if (
    /\b(friend|neighbor|neighbour|classmate|coworker|co-worker|teammate|coach|stranger|boss|colleague|buddy|roommate|acquaintance)\b/.test(
      r
    )
  ) {
    return false;
  }
  if (/^(in[-\s]?laws?|inlaws)$/i.test(r)) return false;
  return /\b(parent|parents|mother|father|mom|dad|mama|papa|son|daughter|brother|sister|sibling|spouse|wife|husband|partner|grandmother|grandfather|grandma|grandpa|grandchild|grandson|granddaughter|aunt|uncle|cousin|niece|nephew|in-law)\b/.test(
    r
  );
}

function memoryHasExplicitNarratorGenderCue(memoryText) {
  const lower = String(memoryText || "").toLowerCase();
  return (
    /\bi\s+am\s+a\s+(man|woman|boy|girl)\b/.test(lower) ||
    /\bi'm\s+a\s+(man|woman|boy|girl)\b/.test(lower) ||
    /\bi\s+was\s+a\s+(man|woman|boy|girl)\b/.test(lower) ||
    /\bas\s+a\s+(man|woman|boy|girl)\b/.test(lower) ||
    /\bmy\s+pronouns\b/.test(lower) ||
    /\b(i|me)\s+use\s+(he|she|they)\b/.test(lower) ||
    /\b(i|me)\s+identify\s+as\b/.test(lower)
  );
}

/** Strips narrator-card gender when likely a stale extraction hallucination (job gender empty + no text cue). */
function stripLikelyHallucinatedNarratorGender(memoryText, job, characters) {
  if (!characters || !characters.length) return characters;
  if (String(job?.gender || "").trim()) return characters;
  if (memoryHasExplicitNarratorGenderCue(memoryText)) return characters;
  let stripped = 0;
  const lastGender = [];
  const out = characters.map((c) => {
    if (!isMemoirNarratorCard(c)) return c;
    const g = String(c.gender || "").trim();
    if (!g) return c;
    stripped += 1;
    lastGender.push(g);
    return { ...c, gender: "" };
  });
  if (stripped > 0) {
    try {
      console.warn(
        JSON.stringify({
          kind: "storybook.narratorGenderHeuristicStripped",
          strippedCount: stripped,
          gendersRemoved: lastGender
        })
      );
    } catch (_) {
      console.warn("storybook.narratorGenderHeuristicStripped", stripped);
    }
  }
  return out;
}

function normalizedFirstToken(name) {
  return String(name || "")
    .replace(/\(me\)/gi, "")
    .trim()
    .split(/\s+/)[0]
    ?.toLowerCase() || "";
}

function levenshtein(a, b) {
  const s = String(a || "");
  const t = String(b || "");
  const n = s.length;
  const m = t.length;
  if (!n) return m;
  if (!m) return n;
  const dp = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = 0; i <= n; i += 1) dp[i][0] = i;
  for (let j = 0; j <= m; j += 1) dp[0][j] = j;
  for (let i = 1; i <= n; i += 1) {
    for (let j = 1; j <= m; j += 1) {
      const cost = s[i - 1] === t[j - 1] ? 0 : 1;
      dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost);
    }
  }
  return dp[n][m];
}

/**
 * Capitalized name-like tokens from transcript (Swift autoDetectedNames second pass).
 */
/** Tokens that match capitalized-word regex but are almost never person names in memoirs. */
const LIKELY_NOT_NAME_TOKENS = new Set([
  "civic",
  "birthday",
  "birthdays",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
  "monday",
  "tuesday",
  "january",
  "february",
  "march",
  "april",
  "may",
  "june",
  "july",
  "august",
  "september",
  "october",
  "november",
  "december",
  "christmas",
  "thanksgiving",
  "halloween",
  "easter",
  "summer",
  "winter",
  "spring",
  "fall",
  "autumn",
  "once",
  "today",
  "yesterday",
  "tomorrow",
  "panera",
  "bread",
  "iphone",
  "spotify",
  "lake",
  "party",
  "wedding",
  "driving",
  "drive",
  "road",
  "trip",
  "night",
  "morning",
  "afternoon",
  "evening"
]);

function autoDetectNamesInTranscript(memoryText) {
  const text = String(memoryText || "");
  const stopWords = new Set([
    "one",
    "day",
    "we",
    "our",
    "my",
    "me",
    "i",
    "the",
    "a",
    "an",
    "it",
    "and",
    "in",
    "on",
    "at",
    "to",
    "for",
    "with",
    "of",
    "middle",
    "park",
    "woods",
    "creek",
    "all",
    "once",
    "then",
    "later",
    "today",
    "yesterday",
    "tomorrow",
    "here",
    "there",
    "everyone",
    "nobody",
    "someone",
    "everybody",
    "something",
    "nothing"
  ]);
  const detected = [];
  const seen = new Set();
  const re = /\b[A-Z][a-z]{1,20}(?:\s+[A-Z][a-z]{1,20})?\b/g;
  let m;
  while ((m = re.exec(text))) {
    const raw = m[0].trim();
    const ft = normalizedFirstToken(raw);
    if (!ft || stopWords.has(ft) || LIKELY_NOT_NAME_TOKENS.has(ft)) continue;
    const key = raw.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    detected.push(raw);
  }
  return detected;
}

function relationshipSplitKey(rel) {
  const r = String(rel || "")
    .toLowerCase()
    .trim();
  return r || "__none__";
}

function shouldSplitSameFirstName(relA, relB) {
  const a = String(relA || "").trim();
  const b = String(relB || "").trim();
  if (!a && !b) return false;
  if (!a || !b) return false;
  return levenshtein(a, b) > 3;
}

/**
 * Book-level cast canon from ordered memories + profile fallbacks.
 * Lives only in worker memory (no Firestore writes).
 */
function buildCastCanon(orderedEntries, job) {
  /** @type {Map<string, any>} */
  const buckets = new Map();

  /** Identity fields locked across pages; conflicting values are omitted from canon (per-memory roster still supplies wardrobe). */
  const STABLE_IDENTITY_FIELDS = new Set(["gender", "ethnicity", "hairAndFeatures"]);

  const bumpAmbiguous = (row, field) => {
    row.ambiguous = row.ambiguous || {};
    row.ambiguous[field] = true;
  };

  const mergeTrait = (row, field, val, sourceMemoryId) => {
    const v = String(val || "").trim();
    if (!v) return;
    const prev = row[field];
    if (!prev) {
      row[field] = v;
      row._sources = row._sources || {};
      row._sources[field] = [{ value: v, memoryId: sourceMemoryId }];
      return;
    }
    if (prev.toLowerCase() === v.toLowerCase()) return;
    const hist = row._sources[field] || [{ value: prev, memoryId: null }];
    hist.push({ value: v, memoryId: sourceMemoryId });
    row._sources[field] = hist;
    const counts = {};
    for (const h of hist) {
      const k = h.value.toLowerCase();
      counts[k] = (counts[k] || 0) + 1;
    }
    const ranked = Object.entries(counts).sort((a, b) => b[1] - a[1]);
    const topLower = ranked[0][0];
    const winnerObj = [...hist].reverse().find((h) => h.value.toLowerCase() === topLower);
    row[field] = winnerObj ? winnerObj.value : prev;
    if (STABLE_IDENTITY_FIELDS.has(field) && ranked.length > 1) {
      const distinctValues = new Set(hist.map((h) => h.value.toLowerCase()));
      if (distinctValues.size > 1) {
        bumpAmbiguous(row, field);
        row[field] = "";
        return;
      }
    }
    if (ranked.length > 1 && ranked[0][1] === ranked[1][1]) bumpAmbiguous(row, field);
  };

  const mergeAgeRange = (row, char, sourceMemoryId) => {
    const ageStr = String(char.age || "").trim();
    if (!ageStr) return;
    const nums = ageStr.match(/\d+/g);
    if (!nums || !nums.length) return;
    const n = parseInt(nums[0], 10);
    if (n < 1 || n > 120) return;
    if (!row.ageRange) row.ageRange = [n, n];
    else {
      row.ageRange[0] = Math.min(row.ageRange[0], n);
      row.ageRange[1] = Math.max(row.ageRange[1], n);
    }
    row._ageSources = row._ageSources || [];
    row._ageSources.push({ age: n, memoryId: sourceMemoryId });
  };

  const mergeDist = (row, char) => {
    const d = String(char.distinguishingFeatures || "").trim();
    if (!d) return;
    row.distinguishingFeatures = row.distinguishingFeatures || [];
    if (!row.distinguishingFeatures.some((x) => x.toLowerCase() === d.toLowerCase())) {
      row.distinguishingFeatures.push(d);
    }
    row.distinguishingFeatures = row.distinguishingFeatures.slice(0, 3);
  };

  const upsertCharacter = (char, sourceMemoryId) => {
    const nameToken = normalizedFirstToken(char.name);
    if (!nameToken) return;
    const relKey = relationshipSplitKey(char.relationshipToNarrator);
    const relRaw = String(char.relationshipToNarrator || "").trim();
    let compositeKey = `${nameToken}::${relKey}`;
    let splitIdx = 2;

    while (buckets.has(compositeKey)) {
      const existing = buckets.get(compositeKey);
      const exRel = String(existing.relationshipRaw || "").trim();
      if (!relRaw && !exRel) break;
      if (relRaw && exRel && relRaw.toLowerCase() === exRel.toLowerCase()) break;
      if (relRaw && exRel && !shouldSplitSameFirstName(exRel, relRaw)) break;
      compositeKey = `${nameToken}::${relKey}__split${splitIdx}`;
      splitIdx += 1;
    }

    if (!buckets.has(compositeKey)) {
      buckets.set(compositeKey, {
        key: compositeKey,
        nameToken,
        displayLabel: String(char.name || "").trim() || nameToken,
        relationshipRaw: relRaw,
        relSubKey: relKey,
        memoryIds: new Set(),
        ambiguous: {}
      });
    }
    const row = buckets.get(compositeKey);
    row.memoryIds.add(sourceMemoryId);

    mergeTrait(row, "gender", char.gender, sourceMemoryId);
    mergeTrait(row, "ethnicity", char.ethnicity, sourceMemoryId);
    mergeTrait(row, "hairAndFeatures", char.hairAndFeatures, sourceMemoryId);
    mergeAgeRange(row, char, sourceMemoryId);
    mergeDist(row, char);

    const clothes = String(char.clothes || "").trim();
    if (clothes) {
      row.clothesByMemory = row.clothesByMemory || {};
      row.clothesByMemory[sourceMemoryId] = clothes;
    }
  };

  for (const entry of orderedEntries || []) {
    const mid = entry.id;
    const details = parseCharacterDetails(entry.characterDetails);
    if (details && details.characters && details.characters.length) {
      for (const c of details.characters) upsertCharacter(c, mid);
    }
    const detected = autoDetectNamesInTranscript(entry.transcription || "");
    for (const dn of detected) {
      upsertCharacter({ name: dn, relationshipToNarrator: "", age: "", gender: "", ethnicity: "", hairAndFeatures: "" }, mid);
    }
  }

  const profileTok = normalizedFirstToken(job.profileName);
  if (profileTok) {
    let profileInCast = false;
    for (const row of buckets.values()) {
      if (row.nameToken === profileTok) {
        profileInCast = true;
        break;
      }
    }
    if (!profileInCast) {
      const compositeKey = `${profileTok}::__narrator__`;
      buckets.set(compositeKey, {
        key: compositeKey,
        nameToken: profileTok,
        displayLabel: String(job.profileName || "").trim() || profileTok,
        relationshipRaw: "memoir narrator",
        relSubKey: relationshipSplitKey("memoir narrator"),
        memoryIds: new Set(),
        ambiguous: {},
        isSynthesized: true,
        gender: String(job.gender || "").trim(),
        ethnicity: String(job.profileEthnicity || "").trim(),
        hairAndFeatures: String(job.faceDescription || "").trim()
      });
    }
  }

  const rows = [];
  for (const row of buckets.values()) {
    if (profileTok && row.nameToken === profileTok) {
      if (!row.ethnicity && job.profileEthnicity) row.ethnicity = String(job.profileEthnicity).trim();
      if (!row.gender && job.gender) row.gender = String(job.gender).trim();
    }
    const ambiguousKeys = Object.keys(row.ambiguous || {}).filter((k) => row.ambiguous[k]);
    const ambiguousHairEthnicityGender =
      ambiguousKeys.some((k) => ["ethnicity", "gender", "hairAndFeatures"].includes(k)) || false;
    rows.push({
      ...row,
      canonAmbiguous: ambiguousHairEthnicityGender,
      ambiguousFields: ambiguousKeys
    });
  }

  return {
    rows,
    buckets
  };
}

/**
 * @param {any} row
 * @param {{ forImagePrompt?: boolean, job?: any }} [options]
 * When `forImagePrompt` is true and the row is the synthesized narrator with a relationship-style profile name,
 * use "the memoir narrator" instead of "Grandparent" so Gemini does not read the label as an age cue.
 * Omit `forImagePrompt` (or pass false) for Firestore-facing strings like `protagonistCanonCard`.
 */
function canonRowToPromptLine(row, options = {}) {
  const forImagePrompt = !!options.forImagePrompt;
  const job = options.job;
  const bits = [];
  let label = row.displayLabel || row.nameToken;
  if (forImagePrompt && row.isSynthesized && job && isRelationshipStyleProfileName(job.profileName)) {
    label = "the memoir narrator";
  }
  bits.push(label);
  const rel = String(row.relationshipRaw || "").trim();
  if (rel) bits.push(`(${rel})`);
  const traits = [];
  if (row.gender) traits.push(String(row.gender).toLowerCase());
  if (row.ethnicity) traits.push(row.ethnicity);
  if (row.hairAndFeatures) traits.push(row.hairAndFeatures);
  if (row.ageRange) traits.push(`age ~${row.ageRange[0]}–${row.ageRange[1]}`);
  if (row.distinguishingFeatures && row.distinguishingFeatures.length) {
    traits.push(`notes: ${row.distinguishingFeatures.join("; ")}`);
  }
  if (row.canonAmbiguous) {
    traits.push("appearance ambiguous across memories — prefer headshot reference and MEMORY CONTEXT for likeness");
  }
  const ageHint = forImagePrompt && row.isSynthesized && job ? narratorVisualAgeHintForImagePrompt(job) : "";
  if (ageHint && !traits.some((t) => t.includes("visual age"))) traits.push(ageHint);
  if (traits.length) bits.push(`— ${traits.join(", ")}`);
  return bits.join(" ");
}

function filterCanonRowsForEntry(castCanon, entry) {
  if (!castCanon || !castCanon.rows || !castCanon.rows.length) return [];
  const mid = entry.id;
  const details = parseCharacterDetails(entry.characterDetails);
  const namesInDetails = new Set((details?.characters || []).map((c) => normalizedFirstToken(c.name)).filter(Boolean));
  const transcriptLower = String(entry.transcription || "").toLowerCase();
  const detailsBlob = JSON.stringify(details || {}).toLowerCase();

  return castCanon.rows.filter((row) => {
    if (row.isSynthesized) return true;
    let inTranscript = false;
    try {
      const re = new RegExp(`\\b${escapeRegex(row.nameToken)}\\b`, "i");
      inTranscript = re.test(transcriptLower);
    } catch (_) {
      /* ignore */
    }
    const inDetailsToken = namesInDetails.has(row.nameToken);
    let inDetailsWord = false;
    try {
      const re2 = new RegExp(`\\b${escapeRegex(row.nameToken)}\\b`, "i");
      inDetailsWord = re2.test(detailsBlob);
    } catch (_) {
      /* ignore */
    }
    const anchored = inTranscript || inDetailsToken || inDetailsWord;
    if (!anchored) return false;
    // Rows sourced only from other memories must still appear by name in THIS memory's text/cards (anchored).
    if (row.memoryIds && row.memoryIds.size && !row.memoryIds.has(mid)) {
      return anchored;
    }
    return true;
  });
}

function enrichEntryCharacterDetailsFromCanon(entry, castCanon, job) {
  const details = parseCharacterDetails(entry.characterDetails) || { characters: [] };
  const rows = filterCanonRowsForEntry(castCanon, entry);
  const rowByToken = new Map(rows.map((r) => [r.nameToken, r]));

  const merged = (details.characters || []).map((c) => {
    const tok = normalizedFirstToken(c.name);
    const row = rowByToken.get(tok);
    const x = { ...c };
    if (row) {
      if (!x.ethnicity && row.ethnicity) x.ethnicity = row.ethnicity;
      if (!x.gender && row.gender) x.gender = row.gender;
      if (!x.hairAndFeatures && row.hairAndFeatures) x.hairAndFeatures = row.hairAndFeatures;
      const profileTok = normalizedFirstToken(job.profileName);
      if (tok === profileTok) {
        if (!x.ethnicity && job.profileEthnicity) x.ethnicity = String(job.profileEthnicity).trim();
        if (!x.gender && job.gender) x.gender = String(job.gender).trim();
      }
    }
    return x;
  });

  const existingTokens = new Set(merged.map((c) => normalizedFirstToken(c.name)).filter(Boolean));
  const detected = autoDetectNamesInTranscript(entry.transcription || "");
  let synthId = 900000;
  for (const dn of detected) {
    const tok = normalizedFirstToken(dn);
    if (!tok || existingTokens.has(tok)) continue;
    const row = rows.find((r) => r.nameToken === tok);
    if (!row) continue;
    const traits = [];
    if (row.gender) traits.push(String(row.gender).toLowerCase());
    if (row.ethnicity) traits.push(row.ethnicity);
    if (row.hairAndFeatures) traits.push(row.hairAndFeatures);
    merged.push({
      id: synthId++,
      name: row.displayLabel || dn,
      relationshipToNarrator: row.relationshipRaw || "",
      age: "",
      gender: row.gender || "",
      ethnicity: row.ethnicity || "",
      hairAndFeatures: row.hairAndFeatures || "",
      clothes: "",
      combinedAppearance: traits.length ? traits.join(", ") : ""
    });
    existingTokens.add(tok);
  }

  const withNarrator = prependSynthesizedNarratorForSceneContext(castCanon, merged, job);
  return stringifyCharacterDetails({ characters: withNarrator });
}

/**
 * When the profile name is not already a character card, prepend a row so scene/title LLMs
 * map "I"/"me"/"my" to the memoir subject (same source as synthesized canon row).
 */
function prependSynthesizedNarratorForSceneContext(castCanon, merged, job) {
  const profileName = String(job.profileName || "").trim();
  if (!profileName) return merged;
  const pt = normalizedFirstToken(profileName);
  if (!pt) return merged;
  const hasProfile = merged.some((c) => normalizedFirstToken(c.name) === pt);
  if (hasProfile) return merged;
  const synthRow = castCanon?.rows?.find((r) => r.isSynthesized && r.nameToken === pt);
  const displayName = imageNarratorDisplayName(job);
  const ageHint = narratorVisualAgeHintForImagePrompt(job);
  const hfBase = synthRow
    ? String(synthRow.hairAndFeatures || job.faceDescription || "").trim()
    : String(job.faceDescription || "").trim();
  const hairAndFeatures = [hfBase, ageHint].filter(Boolean).join("; ");
  const narratorChar = synthRow
    ? {
        id: "__narrator__",
        name: displayName,
        relationshipToNarrator: "memoir narrator (the 'I' in this memory)",
        age: "",
        gender: String(synthRow.gender || job.gender || "").trim(),
        ethnicity: String(synthRow.ethnicity || job.profileEthnicity || "").trim(),
        hairAndFeatures,
        clothes: "",
        combinedAppearance: "",
        isSynthesizedNarrator: true,
        isSynthesized: true
      }
    : {
        id: "__narrator__",
        name: displayName,
        relationshipToNarrator: "memoir narrator (the 'I' in this memory)",
        age: "",
        gender: String(job.gender || "").trim(),
        ethnicity: String(job.profileEthnicity || "").trim(),
        hairAndFeatures,
        clothes: "",
        combinedAppearance: "",
        isSynthesizedNarrator: true,
        isSynthesized: true
      };
  return [narratorChar, ...merged];
}

function nameMatchesProfileFirstToken(characterDetailsStr, transcript, profileName) {
  const pt = normalizedFirstToken(profileName);
  if (!pt) return false;
  try {
    const re = new RegExp(`\\b${escapeRegex(pt)}\\b`, "i");
    if (re.test(String(transcript || ""))) return true;
  } catch (_) {
    /* ignore */
  }
  const d = parseCharacterDetails(characterDetailsStr);
  for (const c of d?.characters || []) {
    if (normalizedFirstToken(c.name) === pt) return true;
    if (c.isSynthesizedNarrator || c.id === "__narrator__") return true;
  }
  return false;
}

/**
 * Headshot attach policy (plan): skip only when likelyAbsent AND no profile first-token match in text/cards.
 */
function shouldAttachHeadshot({ narratorPresence, headshotBuf, characterDetailsStr, transcript, profileName }) {
  if (!headshotBuf) return { attach: false, reason: "no_headshot" };
  const matchesProfile = nameMatchesProfileFirstToken(characterDetailsStr, transcript, profileName);
  if (narratorPresence === "likelyAbsent" && !matchesProfile) {
    return { attach: false, reason: "likely_absent_no_profile_token_match" };
  }
  if (matchesProfile) return { attach: true, reason: "profile_first_token_match" };
  if (narratorPresence !== "likelyAbsent") return { attach: true, reason: "narrator_not_likely_absent" };
  return { attach: true, reason: "fallback_attach" };
}

function traitListFromCharacter(char) {
  const clothBlob = [
    char.clothes,
    char.clothing,
    char.accessories,
    char.appearance,
    char.physicalDescription,
    char.hairAndFeatures
  ]
    .filter(Boolean)
    .join(" ");
  const dist = [];
  const distRe =
    /\b(texas a&m|a&m aggies|aggies|jersey|uniform|hoodie|camera|guitar|glasses|beard|moustache|mustache|hat|baseball cap|comb-?over|boots|cleats)\b/gi;
  let dm;
  while ((dm = distRe.exec(clothBlob))) {
    const tok = dm[0];
    if (!dist.some((x) => x.toLowerCase() === tok.toLowerCase())) dist.push(tok);
  }
  const traits = [];
  if (dist.length) {
    traits.push(`distinguishing prop / wardrobe (must appear): ${dist.join(", ")}`);
  }
  if (char.age) traits.push(`age ${char.age}`);
  if (char.gender) traits.push(String(char.gender).toLowerCase());
  if (char.ethnicity) traits.push(char.ethnicity);
  if (char.hairAndFeatures) traits.push(char.hairAndFeatures);
  if (char.clothes) traits.push(`wearing ${char.clothes}`);
  const rel = String(char.relationshipToNarrator || "").toLowerCase();
  const isMemoirNarrator = rel.includes("memoir narrator");
  const hasStrongVisual =
    dist.length > 0 ||
    (char.age && String(char.age).trim()) ||
    (char.gender && String(char.gender).trim()) ||
    (char.ethnicity && String(char.ethnicity).trim()) ||
    (char.hairAndFeatures && String(char.hairAndFeatures).trim()) ||
    (char.clothes && String(char.clothes).trim()) ||
    (char.combinedAppearance && String(char.combinedAppearance).trim());
  if (!isMemoirNarrator && !hasStrongVisual) {
    traits.push(
      "visually distinct from every other named character (different face than the memoir narrator — not a clone of the headshot subject)"
    );
  }
  if (!traits.length && char.combinedAppearance) traits.push(char.combinedAppearance);
  return traits;
}

function deriveSubjectName(details) {
  if (!details || !details.characters) return null;
  const nameMarkers = ["(me)", "(narrator)", "(self)", "(main)", "(i)"];
  for (const marker of nameMarkers) {
    const me = details.characters.find((c) => String(c.name || "").toLowerCase().includes(marker));
    if (me) return me.name;
  }
  const narratorRels = ["me", "self", "myself", "narrator", "main character", "the narrator", "i am"];
  for (const rel of narratorRels) {
    const narrator = details.characters.find((c) => {
      const r = String(c.relationshipToNarrator || "").toLowerCase();
      return r === rel || r.includes(rel);
    });
    if (narrator) return narrator.name;
  }
  const firstChar = details.characters[0];
  if (
    firstChar &&
    !String(firstChar.relationshipToNarrator || "").trim() &&
    details.characters.slice(1).some((c) => String(c.relationshipToNarrator || "").trim())
  ) {
    return firstChar.name;
  }
  return null;
}

function narratorScore(char, details, derivedNarratorName, sceneTextForNarratorScoring) {
  let score = 0;
  const name = String(char.name || "").toLowerCase().trim();
  const relationship = String(char.relationshipToNarrator || "").toLowerCase().trim();
  const nameMarkers = ["(me)", "(narrator)", "(self)", "(main)", "(i)"];
  if (nameMarkers.some((m) => name.includes(m))) score += 100;
  const narratorRels = ["me", "self", "myself", "narrator", "main character", "the narrator", "i am", "this is me"];
  if (narratorRels.some((r) => relationship === r || relationship.includes(r))) score += 100;
  if (details.characters.length === 1) score += 100;
  if (details.characters[0] && details.characters[0].id === char.id) score += 30;
  if (derivedNarratorName) {
    const charFirst = name.split(/\s+/)[0]?.replace(/\(me\)/gi, "").trim() || "";
    const narrFirst = String(derivedNarratorName).toLowerCase().split(/\s+/)[0]?.replace(/\(me\)/gi, "").trim() || "";
    if (charFirst && narrFirst && charFirst === narrFirst) score += 20;
  }
  const sceneText = (sceneTextForNarratorScoring || "").toLowerCase();
  if (sceneText) {
    const otherCharNames = details.characters.filter((c) => c.id !== char.id).map((c) => String(c.name || "").toLowerCase());
    for (const otherName of otherCharNames) {
      if (sceneText.includes("narrator") && sceneText.includes(otherName) && !sceneText.includes(name)) {
        score += 15;
        break;
      }
    }
    if (sceneText.includes("only") && sceneText.includes("people")) {
      const mentionedChars = otherCharNames.filter((n) => sceneText.includes(n));
      if (mentionedChars.length === 1 && !sceneText.includes(name)) score += 15;
    }
  }
  return score;
}

function countRegexMatches(pattern, text) {
  try {
    const re = new RegExp(pattern, "gi");
    const m = text.match(re);
    return m ? m.length : 0;
  } catch (_) {
    return 0;
  }
}

function inferNarratorPresence(memoryText, entryChapter, profileName) {
  const lower = String(memoryText || "").toLowerCase();
  const strongAbsentPatterns = [
    /\bwithout me\b/,
    /\bnot me\b/,
    /\bi was not there\b/,
    /\bi wasn't there\b/,
    /\bi did not attend\b/,
    /\bi didn't attend\b/,
    /\bthey told me about\b/,
    /\bi heard about\b/,
    /\bhe told me about\b/,
    /\bshe told me about\b/,
    /\bmy (mom|dad|friend|brother|sister|wife|husband|partner) told me\b/
  ];
  const selfExperiencePatterns = [
    /\bmy birthday\b/,
    /\bwhen i was\b/,
    /\bi remember\b/,
    /\bour family\b/,
    /\bmy first\b/,
    /\bwe (went|were|had|celebrated|traveled|visited)\b/
  ];
  const narratorAbsentExplicit = strongAbsentPatterns.some((p) => p.test(lower));
  const firstPersonHits = countRegexMatches("\\b(i|me|my|mine|we|our|us)\\b", lower);
  const firstPersonDetected = firstPersonHits > 0;

  const reasons = [];
  let presence = "uncertain";
  let score = 0;

  if (narratorAbsentExplicit) {
    presence = "likelyAbsent";
    score = -100;
    reasons.push("explicit narrator-absent phrasing");
  } else if (firstPersonHits > 0) {
    presence = "likelyPresent";
    score = Math.min(120, firstPersonHits * 20);
    reasons.push(`first-person cues x${firstPersonHits}`);
  } else {
    score = 0;
    reasons.push("no first-person and no explicit absence pattern");
    for (const p of selfExperiencePatterns) {
      if (p.test(lower)) {
        reasons.push("self-experience context (weak)");
        break;
      }
    }
    if (String(entryChapter || "").trim()) reasons.push("chapter metadata present");
    if (profileName) {
      const token = String(profileName).trim().split(/\s+/)[0];
      if (token) {
        try {
          const esc = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
          if (new RegExp(`\\b${esc}\\b`, "i").test(lower)) {
            reasons.push("mentions profile name (weak)");
          }
        } catch (_) {
          /* ignore */
        }
      }
    }
  }

  const shouldAttachHeadshot = presence !== "likelyAbsent";
  return {
    presence,
    reason: reasons.length ? reasons.join(", ") : "no clear narrator signal",
    firstPersonDetected,
    confidenceScore: score,
    shouldAttachHeadshot
  };
}

function buildCharacterContextFromDetails(characterDetailsString, job, memoryText = "") {
  const details = parseCharacterDetails(characterDetailsString);
  if (!details || !details.characters || !details.characters.length) return "";
  const stripped = stripLikelyHallucinatedNarratorGender(String(memoryText || ""), job, details.characters);
  const characters = normalizeCardDisplayNames(stripped, job);
  const characterDescriptions = [];
  for (const rawCharacter of characters) {
    const character = { ...rawCharacter };
    const isMem = String(character.relationshipToNarrator || "").toLowerCase().includes("memoir narrator");
    if (!character.ethnicity && job.profileEthnicity && isMem) {
      character.ethnicity = String(job.profileEthnicity).trim();
    }
    if (
      !character.ethnicity &&
      job.profileEthnicity &&
      !isMem &&
      isFamilyOfNarrator(character.relationshipToNarrator)
    ) {
      character.ethnicity = String(job.profileEthnicity).trim();
    }
    let description;
    if (character.isSynthesizedNarrator) {
      const displayName = character.name && String(character.name).trim() ? character.name : "Narrator";
      description = `${displayName} - memoir narrator (the 'I' in this memory)`;
    } else {
      description = character.name && String(character.name).trim() ? character.name : "A person";
    }
    const traits = [];
    if (character.age) traits.push(`age ${character.age}`);
    if (character.gender) traits.push(String(character.gender).toLowerCase());
    if (character.ethnicity) traits.push(character.ethnicity);
    if (character.hairAndFeatures) traits.push(character.hairAndFeatures);
    if (character.clothes) traits.push(`wearing ${character.clothes}`);
    if (!character.ethnicity && !character.hairAndFeatures && !character.clothes && character.combinedAppearance) {
      traits.push(character.combinedAppearance);
    }
    if (character.relationshipToNarrator && !character.isSynthesizedNarrator) {
      traits.push(`(${character.relationshipToNarrator})`);
    }
    if (traits.length) description += ` - ${traits.join(", ")}`;
    characterDescriptions.push(description);
  }
  return `SCENE CHARACTERS: ${characterDescriptions.join("; ")}. `;
}

function fallbackNarratorCharacterLine(characterIndex, profileName, hasHeadshot, job) {
  const j = job || {};
  const pname = String(profileName || j.profileName || "").trim();
  const name = imageNarratorDisplayName({ ...j, profileName: pname });
  const ageHint = narratorVisualAgeHintForImagePrompt({ ...j, profileName: pname });
  if (hasHeadshot) {
    return `Character ${characterIndex}: ${name} - narrator (appearance guided by provided headshot image)`;
  }
  const traits = [];
  if (j.profileEthnicity) traits.push(String(j.profileEthnicity).trim());
  if (j.gender) traits.push(`presenting as ${String(j.gender).toLowerCase()}`);
  if (j.otherDetails) traits.push(String(j.otherDetails).trim());
  if (ageHint && !traits.some((t) => t.includes("visual age"))) traits.push(ageHint);
  if (!traits.length) {
    return `Character ${characterIndex}: ${name} - narrator (no photo: use NARRATOR APPEARANCE section and CHARACTER CARDS for likeness)`;
  }
  return `Character ${characterIndex}: ${name} - narrator - ${traits.join(", ")}`;
}

function narratorIdentityPromptSection(narratorPresence, hasHeadshot, job) {
  if (narratorPresence === "likelyAbsent") return null;
  const lines = [];
  if (hasHeadshot) {
    lines.push(
      "A headshot reference image is attached. Use it as the primary face and appearance anchor for the memoir subject when they appear."
    );
  } else {
    lines.push(
      "No headshot reference image is attached. Follow the text guidance below for the memoir subject; do not substitute a different ethnicity or regional appearance than specified."
    );
  }
  if (job.profileName && String(job.profileName).trim()) {
    const pn = String(job.profileName).trim();
    if (isRelationshipStyleProfileName(pn)) {
      lines.push(
        `Memoir subject (the 'I' in each memory): ${imageNarratorDisplayName(job)}. Account display label (not a visual age cue): ${pn}.`
      );
    } else {
      lines.push(`Memoir subject display name (for 'I' / pronoun mapping): ${pn}.`);
    }
  }
  const bits = [];
  if (job.faceDescription && String(job.faceDescription).trim()) {
    bits.push(
      `Likeness notes (use to disambiguate when reference photo is faint): ${String(job.faceDescription).trim()}`
    );
  }
  if (job.profileEthnicity && String(job.profileEthnicity).trim()) {
    bits.push(
      `Ethnicity / heritage (for skin tone and features): ${String(job.profileEthnicity).trim()}. Render with appropriate skin tone, facial features, and hair characteristics for this heritage.`
    );
  }
  if (job.gender && String(job.gender).trim()) bits.push(`presenting as ${String(job.gender).toLowerCase().trim()}`);
  if (job.otherDetails && String(job.otherDetails).trim()) bits.push(String(job.otherDetails).trim());
  const ageHint = narratorVisualAgeHintForImagePrompt(job);
  if (ageHint && !bits.some((b) => b.includes("visual age"))) bits.push(ageHint);
  if (bits.length) lines.push(`Apply when the memoir subject or narrator is shown: ${bits.join("; ")}.`);
  else if (!hasHeadshot) {
    lines.push("If CHARACTER CARDS list ethnicity or heritage for a named person, render it consistently.");
  }
  if (narratorPresence !== "likelyAbsent") {
    lines.push(
      "Narrator must appear in the artwork when the memory implies they were physically present — not implied, not off-frame, not a disembodied voice."
    );
  }
  return lines.join("\n");
}

/** Stable shape for memoir narrator when profile name is absent from character cards. */
function synthesizeNarratorRow(job) {
  const name = imageNarratorDisplayName(job);
  const ageHint = narratorVisualAgeHintForImagePrompt(job);
  const hf = [String(job.faceDescription || "").trim(), ageHint].filter(Boolean).join("; ");
  return {
    id: "__narrator__",
    name,
    relationshipToNarrator: "memoir narrator",
    age: "",
    gender: String(job.gender || "").trim(),
    ethnicity: String(job.profileEthnicity || "").trim(),
    hairAndFeatures: hf,
    clothes: "",
    combinedAppearance: "",
    isSynthesized: true,
    isSynthesizedNarrator: true
  };
}

function isMemoirNarratorCard(c) {
  return String(c.relationshipToNarrator || "").toLowerCase().includes("memoir narrator");
}

function narratorCardMergeScore(c) {
  let s = 0;
  const nm = String(c.name || "").trim();
  if (nm && !/^i$/i.test(nm)) s += 2;
  for (const k of [
    "hairAndFeatures",
    "physicalDescription",
    "appearance",
    "ethnicity",
    "gender",
    "age",
    "clothes",
    "clothing",
    "combinedAppearance"
  ]) {
    if (String(c[k] || "").trim()) s += 1;
  }
  return s;
}

/** Keep a single memoir-narrator card (best-filled) so "I" + "Narrator" do not duplicate in the Gemini roster. */
function dedupeMemoirNarratorCards(characters) {
  if (!characters || !characters.length) return characters;
  const narrIndices = [];
  for (let i = 0; i < characters.length; i += 1) {
    if (isMemoirNarratorCard(characters[i])) narrIndices.push(i);
  }
  if (narrIndices.length <= 1) return characters;
  let bestIdx = narrIndices[0];
  for (const i of narrIndices) {
    if (narratorCardMergeScore(characters[i]) > narratorCardMergeScore(characters[bestIdx])) bestIdx = i;
  }
  return characters.filter((c, i) => !isMemoirNarratorCard(c) || i === bestIdx);
}

function buildCharacterList(entry, job, sceneDescription, includeNarrator) {
  const details = parseCharacterDetails(entry.characterDetails);
  const lines = [];
  let characterIndex = 1;
  const derivedNarratorName = details ? deriveSubjectName(details) : null;

  if (details && details.characters.length) {
    const transcript = String(entry.transcription || "");
    const stripped = stripLikelyHallucinatedNarratorGender(transcript, job, details.characters);
    const normalizedChars = normalizeCardDisplayNames(stripped, job);
    const deduped = dedupeMemoirNarratorCards(normalizedChars);
    const enriched = deduped.map((c) => {
      const x = { ...c };
      const isMem = String(x.relationshipToNarrator || "").toLowerCase().includes("memoir narrator");
      if (!x.ethnicity && job.profileEthnicity && isMem) {
        x.ethnicity = String(job.profileEthnicity).trim();
      }
      if (!x.ethnicity && job.profileEthnicity && !isMem && isFamilyOfNarrator(x.relationshipToNarrator)) {
        x.ethnicity = String(job.profileEthnicity).trim();
      }
      return x;
    });
    const detailsStrForMatch = stringifyCharacterDetails({ characters: enriched });
    let working = enriched.slice();
    if (
      includeNarrator &&
      String(job.profileName || "").trim() &&
      !nameMatchesProfileFirstToken(detailsStrForMatch, transcript, job.profileName)
    ) {
      working = [synthesizeNarratorRow(job), ...working];
    }
    const enrichedDetails = { characters: working };
    let narratorCandidate = working[0];
    let best = -1;
    for (const c of working) {
      const s = narratorScore(c, enrichedDetails, derivedNarratorName, sceneDescription);
      if (s > best) {
        best = s;
        narratorCandidate = c;
      }
    }
    const narratorId = includeNarrator ? narratorCandidate?.id : null;

    if (includeNarrator && narratorCandidate) {
      const traits = traitListFromCharacter(narratorCandidate);
      const rawName = narratorCandidate.name || "Narrator";
      const label =
        narratorCandidate.isSynthesized && rawName.toLowerCase() === "the memoir narrator"
          ? `${rawName} (the 'I' / memoir speaker)`
          : narratorCandidate.isSynthesized && rawName
            ? `${rawName} (memoir narrator)`
            : rawName;
      let line = `Character ${characterIndex}: ${label}`;
      if (traits.length) line += ` - ${traits.join(", ")}`;
      lines.push(line);
      characterIndex += 1;
    } else if (includeNarrator && job.profileName && String(job.profileName).trim()) {
      lines.push(fallbackNarratorCharacterLine(characterIndex, job.profileName, !!job._hasHeadshot, job));
      characterIndex += 1;
    }

    for (const char of working) {
      if (char.id === narratorId) continue;
      let line = `Character ${characterIndex}: ${char.name || "Character"}`;
      const traits = traitListFromCharacter(char);
      if (traits.length) line += ` - ${traits.join(", ")}`;
      lines.push(line);
      characterIndex += 1;
    }
  } else {
    if (includeNarrator && job.profileName && String(job.profileName).trim()) {
      lines.push(fallbackNarratorCharacterLine(characterIndex, job.profileName, !!job._hasHeadshot, job));
      characterIndex += 1;
    }
  }

  return lines.length ? lines.join("\n") : "";
}

function assembleFinalPrompt(
  memoryText,
  characters,
  narratorPresence,
  sceneDescription,
  rawArtStyle,
  customStyle,
  hasHeadshot,
  job,
  styleReferencePreset,
  opts
) {
  const artStyle = normalizeArtStyleKey(rawArtStyle);
  const options = opts || {};
  const styleText = artStyleMemoryIllustrationStyleDescription(artStyle, customStyle);
  const excerpt = sanitizeMemoryContextForPrompt(memoryText);
  const sceneForPrompt = String(sceneDescription || "").trim();
  const canonLines = options.canonLines || [];
  const referenceImageOrder = options.referenceImageOrder || [];

  let antiStyle =
    "Avoid mixing in unrelated illustration genres or default styles not specified in STYLE LOCK.";
  if (artStyle === "kidsBook") {
    antiStyle =
      "Avoid: photorealism, anime, comic halftone, glossy digital cartoon, vector-flat UI illustration, stock-photo lighting.";
  } else if (artStyle === "realistic") {
    antiStyle =
      "Avoid: cartoon outlines, children's-book watercolor softness, comic halftone, flat cel shading.";
  } else if (artStyle === "comic") {
    antiStyle = "Avoid: soft watercolor storybook rendering, photographic realism, painterly textures.";
  }

  const parts = [];

  parts.push("STYLE LOCK (apply strictly — stated once):");
  parts.push(styleText);
  parts.push(`Anti-style / negative list: ${antiStyle}`);
  parts.push("");

  parts.push("REFERENCE IMAGES (inputs are ordered before prompt text — labels match that order):");
  if (!referenceImageOrder.length) {
    parts.push("(No reference images attached — enforce STYLE LOCK from text alone.)");
  } else {
    let idx = 1;
    for (const kind of referenceImageOrder) {
      if (kind === "style") {
        const presetHint = styleReferencePromptHint(artStyle, styleReferencePreset);
        parts.push(
          `REFERENCE IMAGE #${idx} (style anchor): Match medium, brush texture, palette temperature, linework, and overall illustration genre from this image. Compose the scene using SCENE ACTION + MEMORY CONTEXT — only the LOOK comes from this reference.`
        );
        if (presetHint && artStyle === "kidsBook") {
          parts.push(`Preset hint: ${presetHint.split("\n")[0]}`);
        }
        idx += 1;
      } else if (kind === "headshot") {
        parts.push(
          `REFERENCE IMAGE #${idx} (identity / likeness ONLY): Use for recognizable facial identity only. Do NOT copy photographic lighting, skin texture, exposure, or lens look. Re-render the person completely in the STYLE LOCK above. The reference photograph itself MUST NOT appear inside the output image — no inset, no thumbnail, no corner box, no picture-in-picture, no polaroid, no framed photo on a wall/desk/locket, no avatar bubble. It is out-of-frame information only.`
        );
        if (hasHeadshot) {
          const ageOverride = narratorAgeOverrideForPage(String(options.characterDetailsForAge || ""), memoryText);
          if (ageOverride) {
            parts.push(
              `AGE OVERRIDE FOR THIS PAGE: The narrator must be rendered at age ${ageOverride.age} (life stage: ${ageOverride.lifeStage}). Preserve facial identity from the headshot but adjust facial proportions, body proportions, hair length/style, and clothing to match age ${ageOverride.age}. Treat the headshot as identity reference, not as age reference. Re-age the face only: do NOT change ethnicity, skin tone, gender presentation, or facial bone structure beyond age-appropriate development. Identity comes from the headshot reference image; only age changes.`
            );
          }
        }
        idx += 1;
      }
    }
  }
  parts.push("");

  parts.push("CAST FOR THIS PAGE (book continuity + roster):");
  if (canonLines.length) {
    parts.push("Canon (cross-memory continuity):");
    for (const line of canonLines) parts.push(`- ${line}`);
    parts.push("Character roster:");
  }
  if (characters && String(characters).trim()) {
    parts.push(characters);
  } else {
    parts.push("(No character roster — infer people carefully from MEMORY CONTEXT.)");
  }
  parts.push("");

  if (artStyle === "kidsBook") {
    parts.push(
      "FACE FIDELITY (kidsBook): Stylize but preserve distinguishing identity signals as readable cues — hair color and shape, glasses or none, beard or none, skin-tone bucket, height relative to others. Two characters of the same broad ethnicity must remain visually distinguishable from page to page."
    );
    parts.push("");
  }

  parts.push("SCENE ACTION:");
  parts.push(
    "(Render these people and actions visually only — do NOT paint any of these names, sentences, or descriptions as text inside the artwork.)"
  );
  parts.push(sceneForPrompt);
  parts.push("");

  parts.push(
    "MEMORY CONTEXT (for understanding the people-count, mood, and setting only — the words in this paragraph must NEVER appear inside the artwork as captions, labels, or text):"
  );
  parts.push(excerpt);
  parts.push("");

  parts.push("PEOPLE-RENDER LOCK (critical for this page):");
  if (hasHeadshot) {
    parts.push(
      "- Headshot identity anchor: The narrator's facial bone structure, eye shape, skin tone, and ethnic features come PERMANENTLY from the headshot reference image. These never change between pages, regardless of memory text, card fields, or AGE OVERRIDE (AGE OVERRIDE changes apparent age only, not identity)."
    );
  }
  parts.push(
    "- The memoir narrator is the FIRST character in the CHARACTER ROSTER marked with \"memoir narrator\" (or the subject described in Memoir subject / narrator cues). They MUST be visibly drawn as an on-camera person whenever the scene implies they were physically there. They are NOT a voiceover or narrator box — they share the same world space as everyone else."
  );
  parts.push(
    "- If the composition must drop someone, drop a peripheral named friend before dropping the memoir narrator. Never duplicate one listed person to stand in for the narrator."
  );
  parts.push(
    "- When the narrator's listed ethnicity or heritage differs from other characters, keep that contrast truthful; do not repaint the narrator to match the dominant group, and do not erase visibly present named friends."
  );
  parts.push(
    "- Ethnicity rules (this page): Each character lists their own ethnicity in the roster when provided — always render that. When a roster row has empty ethnicity: (a) If their relationship to the narrator is a close family tie (parent, child, sibling, spouse, grandparent, grandchild, aunt, uncle, cousin, niece, nephew, or explicit in-law kin like brother-in-law), softly match the narrator's listed heritage for consistency. (b) For friends, classmates, teammates, coaches, neighbors, strangers, or bare \"in-laws\" (spouse's parents only), do NOT inherit the narrator's heritage — render with naturally varied features that read as distinct people. (c) Never override an explicitly listed ethnicity on any row."
  );
  parts.push(
    "- If two or more named characters have empty appearance fields on the roster, you MUST still render them as clearly different people (different face shape, hair length/color/texture, build, posture, clothing). Never duplicate the headshot subject's face or signature outfit onto unrelated named characters."
  );
  parts.push(
    "- No embedded reference: do NOT paste, composite, frame, or place any attached reference image (especially the headshot) anywhere inside the artwork — no corner thumbnail, no polaroid, no photo on a desk/wall, no avatar overlay, no inset portrait. Reference images are inputs only; they must never appear as visible elements of the scene unless the MEMORY CONTEXT explicitly describes a photograph being held or hung."
  );
  parts.push("");

  parts.push("RULES:");
  parts.push(
    `- Narrator presence hint: ${narratorPresence}. Match visible faces and people-count to MEMORY CONTEXT; do not drop or duplicate people.`
  );
  parts.push(
    "- Faces: when people are present, faces should be visible and distinct (unless MEMORY CONTEXT implies otherwise)."
  );
  const identityBlock = narratorIdentityPromptSection(narratorPresence, hasHeadshot, job || {});
  if (identityBlock && narratorPresence !== "likelyAbsent") {
    parts.push("- Memoir subject / narrator cues:");
    for (const line of identityBlock.split("\n")) {
      if (String(line).trim()) parts.push(`  ${line}`);
    }
    parts.push(
      "  Narrator MUST appear in-frame as a visible person whenever this memory places them in the scene (not off-screen, not symbolic-only)."
    );
  }
  if (artStyle === "realistic") {
    parts.push(
      "- Realistic mode: pull the camera back or soften focus so exact facial detail is not hyper-sharp photograph-style."
    );
  }

  parts.push("");
  parts.push("──────────────────────────────────");
  parts.push(
    "PUBLISHED-PAGE NOTE (final, overrides the above where conflicting): This artwork sits on a published page where typeset text is added by the publisher elsewhere. The illustration itself MUST be wordless: NO painted captions, NO character-name labels, NO narrator commentary strips, NO subtitles, NO speech bubbles, NO dialog, NO list of names, NO sentence reproducing the MEMORY CONTEXT or the SCENE ACTION. Real-world incidental signage that would naturally be in the scene (street signs, store names, jersey numbers, gravestones the user described) is allowed only if mentioned in MEMORY CONTEXT or SCENE ACTION; otherwise omit signage entirely."
  );
  parts.push("──────────────────────────────────");

  return parts.join("\n");
}

function extractJsonObjectFromAssistantText(content) {
  if (!content) return null;
  const start = content.indexOf("{");
  const end = content.lastIndexOf("}");
  if (start >= 0 && end > start) return content.slice(start, end + 1);
  return String(content).trim();
}

function explicitAge(memoryText) {
  const lower = String(memoryText || "").toLowerCase();
  const patterns = [
    /\b(?:i was|when i was|at age|age|turned|turning)\s+(\d{1,2})\b/,
    /\b(\d{1,2})\s*(?:years old|year old|yrs old)\b/
  ];
  for (const re of patterns) {
    const m = lower.match(re);
    if (m && m[1]) {
      const n = parseInt(m[1], 10);
      if (n >= 1 && n <= 110) return n;
    }
  }
  const wordAges = {
    one: 1,
    two: 2,
    three: 3,
    four: 4,
    five: 5,
    six: 6,
    seven: 7,
    eight: 8,
    nine: 9,
    ten: 10,
    eleven: 11,
    twelve: 12,
    thirteen: 13,
    fourteen: 14,
    fifteen: 15,
    sixteen: 16,
    seventeen: 17,
    eighteen: 18,
    nineteen: 19,
    twenty: 20
  };
  const wm = lower.match(/\b(?:i was|when i was|at age|age|turned|turning)\s+([a-z\-]+)\b/);
  if (wm && wm[1]) {
    const token = wm[1].replace(/-/g, " ");
    for (const [word, value] of Object.entries(wordAges)) {
      if (token.includes(word)) return value;
    }
  }
  if (/\b(?:high\s+school\s+)?senior\s+year\b/.test(lower)) return 17;
  if (/\b(?:high\s+school\s+)?junior\s+year\b/.test(lower)) return 16;
  if (/\bsophomore\s+year\b/.test(lower)) return 15;
  if (/\bfreshman\s+year\b/.test(lower)) return 14;
  return null;
}

/**
 * Parse free-form age from character card (e.g. "early 20s", "21", "teen") for book ordering.
 */
function ageStringToInt(s) {
  const t = String(s || "")
    .trim()
    .toLowerCase();
  if (!t) return null;
  const m = t.match(/\b(\d{1,3})\b/);
  if (m) {
    const n = parseInt(m[1], 10);
    if (n >= 1 && n <= 120) return n;
  }
  if (/\bteen(s)?\b|^teen\b|adolescent\b/.test(t)) return 16;
  if (/\b(toddler|preschool)\b/.test(t)) return 3;
  if (/\b(child|children)\b/.test(t) && !/\bgrand/.test(t)) return 10;
  if (/\b(elderly|senior)\b/.test(t)) return 75;
  if (/\b80s\b|eighties\b/.test(t)) return 82;
  if (/\b70s\b|seventies\b/.test(t)) return 72;
  if (/\b60s\b|sixties\b/.test(t)) return 65;
  if (/\b50s\b|fifties\b/.test(t)) return 52;
  if (/\b40s\b|forties\b/.test(t)) return 45;
  if (/\b30s\b|thirties\b/.test(t)) return 35;
  if (/\b20s\b|twenties\b/.test(t)) return 25;
  if (/\bearly\s+20s\b/.test(t)) return 22;
  if (/\bmid\s+20s\b/.test(t)) return 25;
  if (/\blate\s+20s\b/.test(t)) return 28;
  if (/\bearly\s+30s\b/.test(t)) return 32;
  if (/\bmid\s+30s\b/.test(t)) return 35;
  if (/\blate\s+30s\b/.test(t)) return 38;
  return null;
}

function narratorCharacterRowFromDetailsString(characterDetailsString) {
  try {
    const parsed = parseCharacterDetails(characterDetailsString);
    const chars = parsed?.characters || [];
    if (!chars.length) return null;
    const narratorLike = chars.find((c) => {
      const r = String(c.relationshipToNarrator || "").toLowerCase();
      return r.includes("memoir narrator") || c.isSynthesizedNarrator || c.id === "__narrator__";
    });
    return (
      narratorLike ||
      chars.find((c) => c.isNarrator === true) ||
      chars.find((c) => String(c.isNarrator || "").toLowerCase() === "true") ||
      null
    );
  } catch (_) {
    return null;
  }
}

function ageFromNarratorCard(characterDetailsString) {
  const narr = narratorCharacterRowFromDetailsString(characterDetailsString);
  if (!narr) return null;
  return ageStringToInt(String(narr.age || "").trim());
}

/** Per-page narrator age for image prompts: prefer narrator card age, else explicit age in memory text. */
function narratorAgeOverrideForPage(characterDetailsString, memoryText) {
  const narr = narratorCharacterRowFromDetailsString(characterDetailsString);
  const cardAge = ageStringToInt(String(narr?.age || "").trim());
  const explicit = explicitAge(memoryText);
  const n = cardAge != null ? cardAge : explicit;
  if (n == null) return null;
  const a = parseInt(String(n), 10);
  if (!Number.isFinite(a) || a < 1 || a > 110) return null;
  let lifeStage = "young adult";
  if (a <= 12) lifeStage = "child";
  else if (a <= 17) lifeStage = "teen";
  else if (a <= 35) lifeStage = "young adult";
  else if (a <= 55) lifeStage = "middle aged";
  else lifeStage = "elderly";
  return { age: a, lifeStage };
}

function heuristicAgeFromLifeStage(memoryText) {
  const lower = String(memoryText || "").toLowerCase();
  if (lower.includes("kindergarten")) return 5;
  if (lower.includes("elementary school") || lower.includes("primary school")) return 9;
  if (lower.includes("middle school") || lower.includes("junior high")) return 12;
  if (
    lower.includes("high school") ||
    lower.includes("freshman year") ||
    lower.includes("sophomore year") ||
    lower.includes("junior year") ||
    lower.includes("senior year")
  ) {
    return 16;
  }
  if (
    lower.includes("learned to drive") ||
    lower.includes("learning to drive") ||
    lower.includes("driver's license") ||
    lower.includes("driving test")
  ) {
    return 16;
  }
  if (lower.includes("college") || lower.includes("university") || lower.includes("graduated college")) return 22;
  if (lower.includes("first job") || lower.includes("my first job") || lower.includes("growing up")) return 18;
  if (lower.includes("got married") || lower.includes("our wedding") || lower.includes("married")) return 28;
  if (lower.includes("first child") || lower.includes("my daughter was born") || lower.includes("my son was born")) {
    return 30;
  }
  if (lower.includes("first grandchild") || lower.includes("grandchild was born") || lower.includes("became a grandparent")) {
    return 56;
  }
  if (lower.includes("retired") || lower.includes("retirement")) return 66;
  return null;
}

function aspectRatioFromSize(size) {
  const supported = new Set([
    "1:1",
    "2:3",
    "3:2",
    "3:4",
    "4:3",
    "4:5",
    "5:4",
    "9:16",
    "16:9",
    "21:9"
  ]);
  const trimmed = String(size || "").trim();
  if (supported.has(trimmed)) return trimmed;
  if (trimmed === "1792x1024") return "16:9";
  if (trimmed === "1024x1792") return "9:16";
  return "4:3";
}

/**
 * Shared Gemini generateContent response parser for image-producing calls.
 * Gemini returns HTTP 200 even when content was filtered (e.g. SAFETY block) or
 * the model declined to produce an image — surface exactly why in the thrown error.
 */
function extractImageBufferFromGeminiResponse(data, notFoundMessage) {
  const candidates = data.candidates || [];
  for (const c of candidates) {
    const plist = (c.content && c.content.parts) || [];
    for (const p of plist) {
      const id = p.inlineData || p.inline_data;
      if (id && String(id.mimeType || id.mime_type || "").startsWith("image/")) {
        const b64 = id.data;
        if (b64) return Buffer.from(b64, "base64");
      }
    }
  }

  const firstCandidate = candidates[0] || {};
  const finishReason = firstCandidate.finishReason || null;
  const safetyRatings = firstCandidate.safetyRatings || null;
  const promptFeedback = data.promptFeedback || null;
  const blockReason = promptFeedback ? promptFeedback.blockReason : null;
  // Some responses include a text-only part explaining the refusal — surface it.
  const textParts = ((firstCandidate.content && firstCandidate.content.parts) || [])
    .map((p) => (typeof p.text === "string" ? p.text : ""))
    .filter(Boolean)
    .join(" ")
    .slice(0, 300);

  const reason = blockReason
    ? `blocked: ${blockReason}`
    : finishReason
      ? `finishReason=${finishReason}`
      : "unknown (no image part in response)";
  const detail = textParts ? ` Detail: ${textParts}` : "";
  const err = new Error(`${notFoundMessage} (${reason}).${detail}`);
  err.geminiBody = data;
  err.geminiFinishReason = finishReason;
  err.geminiBlockReason = blockReason;
  err.geminiSafetyRatings = safetyRatings;
  err.geminiTextResponse = textParts || null;
  err.noImageBytes = true;
  throw err;
}

async function generateIllustrationBuffer(geminiApiKey, prompt, size, referenceImageBuffers) {
  const anti =
    "Do not include any words, letters, numbers, captions, signs, logos, or typographic marks in the image.";
  const antiReferenceEcho =
    "Do not embed, paste, frame, or composite any attached reference image (especially a headshot) into the output — references are inputs only and must never appear as a visible element of the artwork (no corner thumbnail, polaroid, inset portrait, or photo prop).";
  const lower = prompt.toLowerCase();
  let promptForGeneration =
    lower.includes("do not include any words") ||
    lower.includes("do not render any words") ||
    lower.includes("no text") ||
    lower.includes("do not include text") ||
    lower.includes("text rendering rule")
      ? prompt
      : `${prompt}\n\n${anti}`;
  if (!lower.includes("do not embed") && !lower.includes("must not appear inside")) {
    promptForGeneration = `${promptForGeneration}\n\n${antiReferenceEcho}`;
  }

  const aspectRatio = aspectRatioFromSize(size);
  const parts = [];
  for (const buf of referenceImageBuffers || []) {
    if (!buf || !buf.length) continue;
    parts.push({
      inline_data: {
        mime_type: "image/jpeg",
        data: Buffer.isBuffer(buf) ? buf.toString("base64") : Buffer.from(buf).toString("base64")
      }
    });
  }
  parts.push({ text: promptForGeneration });

  const body = {
    contents: [{ parts }],
    generationConfig: {
      responseModalities: ["IMAGE"],
      imageConfig: { aspectRatio }
    }
  };

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_IMAGE_MODEL}:generateContent?key=${encodeURIComponent(geminiApiKey)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(180000)
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const apiMsg =
      (data && data.error && data.error.message) ||
      JSON.stringify(data).slice(0, 500);
    const err = new Error(`Gemini image HTTP ${res.status}: ${apiMsg}`);
    err.status = res.status;
    err.geminiBody = data;
    throw err;
  }

  return extractImageBufferFromGeminiResponse(data, "Gemini returned no image");
}

/**
 * Server-side port of `GeminiImageService.editImage`: canvas image first, optional style
 * anchor second, then the edit instruction text. No anti-text/anti-reference-echo clauses —
 * edits may legitimately need to preserve existing text/composition, matching Swift behavior.
 */
async function editImageWithGemini(geminiApiKey, { model, editInstruction, size, imageBuffer, styleAnchorBuffer }) {
  const aspectRatio = aspectRatioFromSize(size);
  const hasStyleAnchor = !!(styleAnchorBuffer && styleAnchorBuffer.length);
  const fullPrompt = `Images are ordered before this text: REFERENCE IMAGE #1 = current illustration (canvas).${
    hasStyleAnchor ? " REFERENCE IMAGE #2 = style anchor (look/medium only)." : ""
  }\nEdit REFERENCE IMAGE #1 according to the instructions below.\n\n${editInstruction}`;

  const parts = [
    {
      inline_data: {
        mime_type: "image/jpeg",
        data: imageBuffer.toString("base64")
      }
    }
  ];
  if (hasStyleAnchor) {
    parts.push({
      inline_data: {
        mime_type: "image/jpeg",
        data: styleAnchorBuffer.toString("base64")
      }
    });
  }
  parts.push({ text: fullPrompt });

  const body = {
    contents: [{ parts }],
    generationConfig: {
      responseModalities: ["IMAGE"],
      imageConfig: { aspectRatio }
    }
  };

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(geminiApiKey)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(170000)
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const apiMsg = (data && data.error && data.error.message) || JSON.stringify(data).slice(0, 500);
    const err = new Error(`Gemini image edit HTTP ${res.status}: ${apiMsg}`);
    err.status = res.status;
    err.geminiBody = data;
    throw err;
  }

  return extractImageBufferFromGeminiResponse(data, "Gemini returned no edited image");
}

/**
 * Server-side port of `GeminiImageService.generateCoverIllustration`'s prompt assembly.
 * `hasHeadshot` selects between the identity-anchored prompt and the strict no-humans prompt.
 */
function buildCoverIllustrationPrompt({
  hasHeadshot,
  profileName,
  ethnicity,
  gender,
  memoryThemes,
  artStyle,
  customStyle,
  printTitle,
  protagonistCanonLine
} = {}) {
  const trimmedThemes = (memoryThemes || []).map((t) => String(t || "").trim()).filter(Boolean);
  const topThemes = trimmedThemes.slice(0, 3);
  const themeGuidance = topThemes.length
    ? `Weave these recurring motifs into the scene (as settings, objects, weather, or symbolism — not as a list): ${topThemes.join(", ")}. One primary focal idea only; avoid collage or crowded montages.`
    : "Use a single strong focal idea with at most one subtle supporting motif.";

  const name = String(profileName || "").trim();
  const resolvedTitle = String(printTitle || "").trim() || (name ? `${name}'s Memoir` : "Memoir");
  const quotedTitle = `⟨${resolvedTitle}⟩`;

  const styleParagraph = artStyleMemoryIllustrationStyleDescription(artStyle, customStyle);
  const stylePreamble = `STYLE LOCK (apply strictly — stated once):\n${styleParagraph}\n${COVER_STYLE_BINDING}\nAnti-style: avoid photorealistic stock-photo lighting, anime, vector-flat UI illustration, or unrelated genres.`;

  const canonLine = String(protagonistCanonLine || "").trim();
  const canonBlock = canonLine ? `\n\nCAST — PROTAGONIST CONTINUITY (cross-page canon):\n${canonLine}` : "";

  if (hasHeadshot) {
    const identityLines = [
      "Include exactly one adult human narrator as the clear focal subject.",
      "Use the reference photo to preserve facial likeness, age cues, and recognizable features.",
      "Clothing and pose may be illustrative; the face must read as the same person as the reference.",
      "The reference photograph is identity guidance only — do NOT embed the photo itself anywhere in the cover. No inset, thumbnail, polaroid, framed portrait, locket, or corner box. The cover must read as one seamless painted illustration."
    ];
    const e = String(ethnicity || "").trim();
    if (e) identityLines.push(`Ethnicity / heritage (for skin tone and features): ${e}.`);
    const g = String(gender || "").trim();
    if (g) identityLines.push(`Gender presentation: ${g}.`);
    const identityBlock = identityLines.join("\n");

    return `BOOK COVER ILLUSTRATION — full bleed, print ready.

${stylePreamble}
${canonBlock}

TYPOGRAPHY (mandatory):
• Paint or hand-letter the book title **inside the artwork** so it reads as part of the illustration (not a separate system font overlay).
• The title must use **exactly** these characters, in this order, including spaces and punctuation: ${quotedTitle}
• Hand-letter with playful per-word color variation drawn from the warm palette (e.g. one word in soft terracotta, the next in dusty blue or warm cream), painted like watercolor lettering — never a system font.
• Do not substitute synonyms, fix spelling, change capitalization, add subtitles, or omit apostrophes.
• Place the title in the **lower third**, large and legible; keep the area behind the letters relatively simple (low clutter) so the words read at small thumbnail size.
• No other legible words, stray letters, captions, logos, barcodes, or watermarks anywhere on the cover.

SUBJECT / LIKENESS:
${identityBlock}

THEME:
${themeGuidance}

COMPOSITION:
• One clear focal subject; calm, jacket-worthy negative space.
• Avoid clutter behind the title strokes; no fake "author name" lines unless they are unreadable texture only.`;
  }

  return `BOOK COVER ILLUSTRATION — full bleed, print ready.

${stylePreamble}
${canonBlock}

TYPOGRAPHY (mandatory):
• Paint or hand-letter the book title **inside the artwork** as integrated art (not a system-font overlay).
• The title must use **exactly** these characters, in this order, including spaces and punctuation: ${quotedTitle}
• Per-word warm-palette color variation (watercolor lettering); never a system font.
• Do not substitute synonyms, change casing, or add other readable words, slogans, logos, or captions.
• Place the title in the **lower third**, large and legible; simplify the background behind the lettering.

NO-HUMANS RULE (strict):
• Do not depict **any** humans, human faces, silhouettes, body parts, crowds, mannequins, statues that read as specific people, or reflections that show people.
• Symbolize people only through objects, places, light, nature, doors, chairs, photographs-without-clear-faces, etc.
• No anthropomorphic animals wearing "character" faces if it reads like a person.

THEME / SETTING (non-figurative):
${themeGuidance}

COMPOSITION:
• Evocative, memoir-appropriate environment or symbolic still-life; one visual idea, uncluttered, professional dust-jacket quality.`;
}

/**
 * Server-side port of `GeminiImageService.generateBackCoverIllustration`'s prompt assembly.
 * Reference image order matches the Swift caller: front cover art first, optional headshot second.
 */
function buildBackCoverIllustrationPrompt({ hasHeadshot, ethnicity, gender, memoryThemes, artStyle, customStyle } = {}) {
  const trimmedThemes = (memoryThemes || []).map((t) => String(t || "").trim()).filter(Boolean);
  const topThemes = trimmedThemes.slice(0, 4);
  const styleParagraph = artStyleMemoryIllustrationStyleDescription(artStyle, customStyle);
  const stylePreamble = `STYLE LOCK (apply strictly):\n${styleParagraph}\n${COVER_STYLE_BINDING}`;

  const themeGuidance = topThemes.length
    ? `Carry forward these memoir motifs while introducing fresh details: ${topThemes.join(", ")}. Keep one clear visual idea.`
    : "Use one coherent environmental motif that feels emotionally connected to the front cover.";

  let identityGuidance;
  if (!hasHeadshot) {
    identityGuidance =
      "If people appear, keep them distant, silhouette-level, or implied through objects and setting. Do not show clear readable faces.";
  } else {
    const lines = [
      "If a person appears, preserve continuity with the front cover subject identity and age cues from references.",
      "This is a back-cover support scene: avoid close-up portraits; keep character presence secondary to environment.",
      "Treat the headshot reference as identity guidance only — the entire back cover must read as one seamless painted illustration in the same medium as the front cover."
    ];
    const e = String(ethnicity || "").trim();
    if (e) lines.push(`Maintain coherent ethnicity cues: ${e}.`);
    const g = String(gender || "").trim();
    if (g) lines.push(`Maintain coherent gender presentation: ${g}.`);
    identityGuidance = lines.join("\n");
  }

  return `BACK COVER ILLUSTRATION — full bleed, print ready.

${stylePreamble}

CONTINUITY:
• The first reference image is the FRONT COVER art. Match its world, palette temperature, lighting logic, era, and emotional tone.
• Create a complementary continuation scene (same story universe), not a duplicate of the front.
• Add at least one new narrative detail that was not dominant on the front cover.

TEXT SAFETY (strict):
• No readable words, letters, logos, signage, watermarks, or captions anywhere.
• Keep the upper-left back-panel area visually calmer (lower contrast, less clutter) so overlay copy remains readable.

THEME:
${themeGuidance}

SUBJECT RULES:
${identityGuidance}

COMPOSITION:
• Professional dust-jacket quality, uncluttered, cohesive with front cover.
• Favor broad shapes and gentle gradients where back-cover marketing text would typically sit.`;
}

async function generateBackCoverPitch(geminiApiKey, prompt) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_TEXT_MODEL}:generateContent?key=${encodeURIComponent(geminiApiKey)}`;
  const body = {
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: { temperature: 0.7, maxOutputTokens: 256 }
  };
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(60000)
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) return null;
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
  return text ? String(text).trim() : null;
}

function isQuestionDrivenMemory(entry) {
  const rawPrompt = String(entry.prompt || "").trim();
  if (!rawPrompt) return false;
  const np = rawPrompt.toLowerCase();
  if (np === "untitled prompt" || np === "untitled") return false;
  if (rawPrompt.endsWith("?")) return true;
  const questionPrefixes = [
    "what",
    "when",
    "where",
    "who",
    "why",
    "how",
    "tell me about",
    "describe",
    "share",
    "think of"
  ];
  return questionPrefixes.some((p) => np.startsWith(`${p} `) || np === p);
}

function loadStyleReferencePng(styleReferencePreset) {
  const preset = styleReferencePreset || "normal";
  const base = preset === "ref1" ? "Ref1" : preset === "ref2" ? "Ref2" : "Refnormal";
  const fp = path.join(__dirname, "assets", "style", `${base}.png`);
  if (fs.existsSync(fp)) return fs.readFileSync(fp);
  return null;
}

function createStorybookAI(openaiApiKey, geminiApiKey) {
  const openai = new OpenAI({ apiKey: openaiApiKey });

  async function chatMini(messages, extra = {}) {
    // gpt-5 models reject max_tokens and non-default temperature, and spend reasoning
    // tokens from the completion budget — normalize legacy params from call sites.
    const { max_tokens: legacyMaxTokens, temperature: _ignoredTemperature, ...rest } = extra;
    const params = {
      model: OPENAI_TEXT_MODEL,
      messages,
      reasoning_effort: "minimal",
      max_completion_tokens: Math.max(Number(legacyMaxTokens) || 512, 128),
      ...rest
    };
    const completion = await openai.chat.completions.create(params);
    return completion.choices[0]?.message?.content || "";
  }

  async function rankMemoriesWithLLM(memories, topN) {
    const requestedCount = Math.max(1, topN);
    const valid = memories.filter((m) => m.id && String(m.transcription || "").trim());
    if (requestedCount >= valid.length) return valid;
    const stubs = valid.map((mem) => {
      const words = String(mem.transcription || "").split(/\s+/);
      const summary = words.slice(0, 100).join(" ");
      return { id: mem.id, summary, chapter: mem.chapter || null };
    });
    const stubStr = JSON.stringify(stubs);
    const system = {
      role: "system",
      content: `You are a memoir editor selecting memories for a printed storybook. Pick the ${requestedCount} most emotionally significant, vivid, and visually rich memories. Prefer variety across different life chapters. Each memory includes a summary and optionally the chapter it belongs to.`
    };
    const user = {
      role: "user",
      content: `Return ONLY JSON { "top": ["uuid1","uuid2"] }. \nMemories: ${stubStr}`
    };
    try {
      const content = await chatMini([system, user], { max_tokens: 512, temperature: 0 });
      const slice = extractJsonObjectFromAssistantText(content) || content;
      const parsed = JSON.parse(slice);
      const ids = parsed.top;
      if (!Array.isArray(ids)) return valid.slice(0, requestedCount);
      const normalized = [];
      const seen = new Set();
      for (const raw of ids) {
        const id = String(raw);
        if (seen.has(id)) continue;
        seen.add(id);
        normalized.push(id);
        if (normalized.length === requestedCount) break;
      }
      if (!normalized.length) return valid.slice(0, requestedCount);
      const order = new Map(normalized.map((id, i) => [id, i]));
      return valid
        .filter((m) => order.has(m.id))
        .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
        .slice(0, requestedCount);
    } catch (e) {
      console.warn("rankMemoriesWithLLM failed", e);
      return valid.slice(0, requestedCount);
    }
  }

  async function extractAge(memoryText, characterDetailsString) {
    const ex = explicitAge(memoryText);
    if (ex != null) return ex;
    const fromCards = ageFromNarratorCard(String(characterDetailsString || ""));
    if (fromCards != null) return fromCards;
    const systemPrompt = `You are a data extraction expert. Your task is to read a user's memory and determine the user's age at the time of the event.
- Look for explicit mentions of age like "I was 13", "when I turned ten", "at age seven".
- If no age is explicitly mentioned, infer a plausible age based on context and life-stage cues.
- You MUST respond with ONLY a single integer number and nothing else. For example: 13.
- If you cannot determine an age with reasonable confidence, respond with 999.`;
    try {
      const responseText = await chatMini(
        [
          { role: "system", content: systemPrompt },
          { role: "user", content: memoryText }
        ],
        { temperature: 0, max_tokens: 5 }
      );
      const trimmed = String(responseText).trim();
      const age =
        parseInt(trimmed, 10) ||
        (trimmed.match(/\d+/) ? parseInt(trimmed.match(/\d+/)[0], 10) : NaN);
      if (age >= 1 && age <= 110 && age !== 999) return age;
      const h = heuristicAgeFromLifeStage(memoryText);
      if (h != null) return h;
    } catch (e) {
      console.warn("extractAge failed", e);
    }
    return 999;
  }

  async function extractVisualScene(rawText, characterContext) {
    const characterGuidance = characterContext
      ? `

CHARACTER INFORMATION PROVIDED:
${characterContext}

Use the exact physical descriptions provided above for each character when describing the scene.`
      : "";
    let narratorName = null;
    if (characterContext && characterContext.startsWith("SCENE CHARACTERS:")) {
      const after = characterContext.slice("SCENE CHARACTERS:".length).trim();
      const firstSemicolon = after.indexOf(";");
      const firstEntry = (firstSemicolon >= 0 ? after.slice(0, firstSemicolon) : after).trim();
      const dashIdx = firstEntry.indexOf(" - ");
      if (dashIdx > 0) {
        narratorName = firstEntry.slice(0, dashIdx).trim();
      }
    }
    const narratorGuidance = narratorName
      ? `

NARRATOR IDENTITY: The first character listed (${narratorName}) is the memoir speaker ("I"/"me"/"my"). They are an ADDITIONAL person in the headcount versus the other named friends — never merge them into a friend. When the memory uses first person, refer to ${narratorName} using that exact listed name. Do not substitute another listed character's name for "I"/"me"/"my".`
      : "";
    const systemPrompt = `You are a visual scene extractor. Extract the key visual moment from this memory.

CRITICAL RULES:
1. **People count is EXACT**.
   - If the FIRST listed character is marked "memoir narrator" (the synthesized narrator), they are an ADDITIONAL person on top of any other listed friends. So "the memoir narrator (memoir narrator), Caleb, Ian, Robbie" = 4 people in the image, not 3.
   - The narrator is NEVER one of the named friends. Do NOT merge them.
   - If the memory says "me and 5 friends" and 5 friends are named, that is 6 people total (narrator + 5 named).
   - Do not drop anyone the memory implies is visibly present; do not invent extra people.
2. **Identify the Key Scene**: Pick the single best on-camera moment. If the memory names a specific small action, object, or prop-heavy beat (someone doing X on/with Y, a telling detail, an unusual posture or location), prioritize that beat over a generic overview of the whole event (e.g. prefer "Granddaughter sits on the cooler eating cherries" over "everyone sits around the dinner table") unless the memory truly has no such detail.
3. **Keep it Simple but Complete**: Describe the setting, who is there, and what they are doing.
4. **No Redundant Descriptions**: Do not describe physical appearance (hair, skin, etc.) as that is handled separately. Just use names.
5. **Direct Style**: Use simple, factual sentences.
6. **Body Position Accuracy**: Preserve the EXACT body positions described in the memory (sitting, standing, laying, kneeling, running, etc.). If the memory says "sitting", the scene MUST describe them sitting. If "laying down", they MUST be laying down. Never change or omit described postures.
7. **Narration words are NOT names**: Capitalized sentence starters like "All", "Once", "Then", "Today", "Yesterday" are narration — never treat them as a person's name or invent a character called that.
8. **Memoir narrator mapping**: The memoir speaker ("I", "me", "my", "we" when meaning the speaker's group) maps to the FIRST character in CHARACTER INFORMATION whose line includes the phrase "memoir narrator". Use that person's exact listed NAME in your paragraph for every first-person reference. Never rename them to a different listed character.
9. **Use names, never collective phrases.** Refer to people by their listed display names. Never write "the group of friends", "the kids", "the boys", "the girls", "the team", "the family", "everyone", or similar collective stand-ins for individually listed people. If five people are listed, write all five names. If you genuinely do not know a name, write "another friend".
10. **Pronoun discipline:** When the listed gender for the memoir narrator (or any listed person) is empty, do NOT invent he/she/his/her for that person. Repeat their exact listed display name or use singular they/them/their. Never swap pronouns between two different listed people.
11. **Roster labels override kin words:** When the source memory uses kin phrases ("his mother", "my dad", "her son") but CHARACTER INFORMATION lists a different display name for that person (e.g. "Mother (the narrator's wife)"), ALWAYS use the roster display name in your paragraph — never copy the kin phrase from the source if it conflicts with the roster.
12. **Narrator gender empty:** When the memoir narrator's listed gender is empty in CHARACTER INFORMATION, do NOT infer gender from the memory text, scene, or cultural priors. Use their listed display name or singular they/them/their for the narrator only.
${narratorGuidance}
${characterGuidance}

Output: One paragraph describing the scene action and participants accurately.`;
    const scene = await chatMini(
      [
        { role: "system", content: systemPrompt },
        { role: "user", content: rawText }
      ],
      { temperature: 0.05 }
    );
    const out = String(scene || rawText).trim() || rawText;
    return out;
  }

  async function extractTitleAndCharacters(memoryText, characterContext) {
    const systemPrompt = `You are a book editor. Your job is to create a title and a 'featuring' list for a memory.

1. Title: Create a short, engaging title (max 5 words).
2. Featuring: List the people in the memory. Format: "Feat: [List]".
   - Use "me" for the narrator.
   - Use first names if known.
   - If names are unknown, count them (e.g., "2 friends", "my mom").
   - Format example: "Feat: me, Robbie, and 2 friends" or "Feat: me and my mom".
   - Keep it concise.

Return ONLY JSON: { "title": "...", "featuring": "..." }`;
    const prompt = `Memory: ${memoryText}

Known Characters: ${characterContext}

Extract title and featuring list.`;
    try {
      const content = await chatMini(
        [
          { role: "system", content: systemPrompt },
          { role: "user", content: prompt }
        ],
        { temperature: 0.3, max_tokens: 100, response_format: { type: "json_object" } }
      );
      const parsed = JSON.parse(content);
      return { title: parsed.title || "A Special Memory", featuring: parsed.featuring || "" };
    } catch (_) {
      return { title: "A Special Memory", featuring: "" };
    }
  }

  return {
    rankMemoriesWithLLM,
    extractAge,
    extractVisualScene,
    extractTitleAndCharacters,
    inferNarratorPresence,
    buildCharacterContextFromDetails,
    buildCharacterList,
    assembleFinalPrompt,
    generateIllustrationBuffer,
    generateBackCoverPitch: (p) => generateBackCoverPitch(geminiApiKey, p),
    loadStyleReferencePng,
    artStyleMemoryIllustrationStyleDescription,
    normalizeArtStyleKey,
    COVER_STYLE_BINDING,
    isQuestionDrivenMemory,
    buildCastCanon,
    enrichEntryCharacterDetailsFromCanon,
    filterCanonRowsForEntry,
    canonRowToPromptLine,
    shouldAttachHeadshot,
    nameMatchesProfileFirstToken
  };
}

module.exports = {
  createStorybookAI,
  normalizeArtStyleKey,
  inferNarratorPresence,
  buildCharacterContextFromDetails,
  buildCharacterList,
  assembleFinalPrompt,
  generateIllustrationBuffer,
  editImageWithGemini,
  uploadPngWithDownloadURL,
  buildCoverIllustrationPrompt,
  buildBackCoverIllustrationPrompt,
  artStyleMemoryIllustrationStyleDescription,
  aspectRatioFromSize,
  loadStyleReferencePng,
  isQuestionDrivenMemory,
  buildCastCanon,
  enrichEntryCharacterDetailsFromCanon,
  filterCanonRowsForEntry,
  canonRowToPromptLine,
  shouldAttachHeadshot,
  nameMatchesProfileFirstToken
};

