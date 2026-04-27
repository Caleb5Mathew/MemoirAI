/**
 * Server-side ports of StoryPageViewModel + GeminiImageService storybook AI helpers.
 * Prompts mirror Swift sources for consistent outputs.
 */

const OpenAI = require("openai");
const path = require("path");
const fs = require("fs");

const GEMINI_IMAGE_MODEL = "gemini-3-pro-image-preview";

function artStyleMemoryIllustrationStyleDescription(artStyle, customText) {
  switch (artStyle) {
    case "kidsBook":
      return "Children's book illustration with soft watercolor style, gentle colors, and hand-drawn warmth. Keep character faces expressive and readable with natural eyes, visible iris/pupil detail, and soft facial features that still feel kid-friendly. NO photorealistic elements, NO detailed textures, NO complex lighting.";
    case "realistic":
      return "Photorealistic image with detailed textures, natural lighting, and lifelike appearance. Render as photograph-quality with natural skin textures, real fabric folds, ambient occlusion, and photographic depth of field. This must look like a real photograph or hyperrealistic digital painting, NOT a cartoon, comic panel, or soft children's-book illustration.";
    case "comic":
      return "Comic book illustration with bold ink outlines, dynamic halftone shading, vibrant colors, dramatic composition, expressive poses, and classic comic book art style. Use thick black ink outlines around all figures and objects. Apply visible halftone dot patterns for shading. Use flat, saturated color fills. This must unmistakably look like a printed comic book panel, NOT a watercolor or soft illustration.";
    case "custom":
    default: {
      const trimmed = String(customText || "an undefined style").trim();
      return `Custom style described as: '${trimmed || "an undefined style"}'. Strictly follow this style direction.`;
    }
  }
}

const COVER_STYLE_BINDING =
  "BINDING INSTRUCTION: Render strictly according to VISUAL STYLE above (medium, linework, color, and lighting). Do not substitute a different illustration genre or default to soft watercolor unless VISUAL STYLE specifies watercolor children's book.";

function styleReferencePromptHint(artStyle, styleReferencePreset) {
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

function traitListFromCharacter(char) {
  const traits = [];
  if (char.age) traits.push(`age ${char.age}`);
  if (char.gender) traits.push(String(char.gender).toLowerCase());
  if (char.ethnicity) traits.push(char.ethnicity);
  if (char.hairAndFeatures) traits.push(char.hairAndFeatures);
  if (char.clothes) traits.push(`wearing ${char.clothes}`);
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
  let score = 0;
  const reasons = [];
  for (const p of strongAbsentPatterns) {
    if (p.test(lower)) {
      score -= 120;
      reasons.push("explicit narrator-absent phrasing");
      break;
    }
  }
  const firstPersonCount = countRegexMatches("\\b(i|me|my|mine|we|our|us)\\b", lower);
  const firstPersonDetected = firstPersonCount > 0;
  if (firstPersonDetected) {
    const firstPersonScore = Math.min(120, firstPersonCount * 20);
    score += firstPersonScore;
    reasons.push(`first-person cues x${firstPersonCount}`);
  }
  for (const p of selfExperiencePatterns) {
    if (p.test(lower)) {
      score += 35;
      reasons.push("self-experience context");
      break;
    }
  }
  if (String(entryChapter || "").trim()) {
    score += 15;
    reasons.push("chapter metadata present");
  }
  if (profileName) {
    const token = String(profileName).trim().split(/\s+/)[0];
    if (token) {
      try {
        const esc = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        if (new RegExp(`\\b${esc}\\b`, "i").test(lower)) {
          score += 10;
          reasons.push("mentions profile name");
        }
      } catch (_) {
        /* ignore */
      }
    }
  }
  let presence = "uncertain";
  if (score >= 60) presence = "likelyPresent";
  else if (score <= -60) presence = "likelyAbsent";
  const shouldAttachHeadshot = presence !== "likelyAbsent";
  return {
    presence,
    reason: reasons.length ? reasons.join(", ") : "no clear narrator signal",
    firstPersonDetected,
    confidenceScore: score,
    shouldAttachHeadshot
  };
}

function buildCharacterContextFromDetails(characterDetailsString, job) {
  const details = parseCharacterDetails(characterDetailsString);
  if (!details || !details.characters || !details.characters.length) return "";
  const characterDescriptions = [];
  for (const rawCharacter of details.characters) {
    const character = { ...rawCharacter };
    if (!character.ethnicity && job.profileEthnicity) character.ethnicity = String(job.profileEthnicity).trim();
    let description = character.name && String(character.name).trim() ? character.name : "A person";
    const traits = [];
    if (character.age) traits.push(`age ${character.age}`);
    if (character.gender) traits.push(String(character.gender).toLowerCase());
    if (character.ethnicity) traits.push(character.ethnicity);
    if (character.hairAndFeatures) traits.push(character.hairAndFeatures);
    if (character.clothes) traits.push(`wearing ${character.clothes}`);
    if (!character.ethnicity && !character.hairAndFeatures && !character.clothes && character.combinedAppearance) {
      traits.push(character.combinedAppearance);
    }
    if (character.relationshipToNarrator) traits.push(`(${character.relationshipToNarrator})`);
    if (traits.length) description += ` - ${traits.join(", ")}`;
    characterDescriptions.push(description);
  }
  return `SCENE CHARACTERS: ${characterDescriptions.join("; ")}. `;
}

function fallbackNarratorCharacterLine(characterIndex, profileName, hasHeadshot, job) {
  const name = String(profileName || "Narrator").trim() || "Narrator";
  if (hasHeadshot) {
    return `Character ${characterIndex}: ${name} - narrator (appearance guided by provided headshot image)`;
  }
  const traits = [];
  if (job.profileEthnicity) traits.push(String(job.profileEthnicity).trim());
  if (job.gender) traits.push(`presenting as ${String(job.gender).toLowerCase()}`);
  if (job.otherDetails) traits.push(String(job.otherDetails).trim());
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
    lines.push(`Memoir subject display name (for 'I' / pronoun mapping): ${String(job.profileName).trim()}.`);
  }
  const bits = [];
  if (job.faceDescription && String(job.faceDescription).trim()) bits.push(String(job.faceDescription).trim());
  if (job.profileEthnicity && String(job.profileEthnicity).trim()) {
    bits.push(
      `Ethnicity / heritage (for skin tone and features): ${String(job.profileEthnicity).trim()}. Render with appropriate skin tone, facial features, and hair characteristics for this heritage.`
    );
  }
  if (job.gender && String(job.gender).trim()) bits.push(`presenting as ${String(job.gender).toLowerCase().trim()}`);
  if (job.otherDetails && String(job.otherDetails).trim()) bits.push(String(job.otherDetails).trim());
  if (bits.length) lines.push(`Apply when the memoir subject or narrator is shown: ${bits.join("; ")}.`);
  else if (!hasHeadshot) {
    lines.push("If CHARACTER CARDS list ethnicity or heritage for a named person, render it consistently.");
  }
  return lines.join("\n");
}

function buildCharacterList(entry, job, sceneDescription, includeNarrator) {
  const details = parseCharacterDetails(entry.characterDetails);
  const lines = [];
  let characterIndex = 1;
  const derivedNarratorName = details ? deriveSubjectName(details) : null;

  if (details && details.characters.length) {
    const enriched = details.characters.map((c) => {
      const x = { ...c };
      if (!x.ethnicity && job.profileEthnicity) x.ethnicity = String(job.profileEthnicity).trim();
      return x;
    });
    const enrichedDetails = { characters: enriched };
    let narratorCandidate = enriched[0];
    let best = -1;
    for (const c of enriched) {
      const s = narratorScore(c, enrichedDetails, derivedNarratorName, sceneDescription);
      if (s > best) {
        best = s;
        narratorCandidate = c;
      }
    }
    const narratorId = includeNarrator ? narratorCandidate?.id : null;

    if (includeNarrator && narratorCandidate) {
      const traits = traitListFromCharacter(narratorCandidate);
      let line = `Character ${characterIndex}: ${narratorCandidate.name || "Narrator"}`;
      if (traits.length) line += ` - ${traits.join(", ")}`;
      lines.push(line);
      characterIndex += 1;
    } else if (includeNarrator && job.profileName && String(job.profileName).trim()) {
      lines.push(fallbackNarratorCharacterLine(characterIndex, job.profileName, !!job._hasHeadshot, job));
      characterIndex += 1;
    }

    for (const char of enriched) {
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
  artStyle,
  customStyle,
  hasHeadshot,
  job,
  styleReferencePreset
) {
  const parts = [];
  const styleText = artStyleMemoryIllustrationStyleDescription(artStyle, customStyle);
  parts.push(`IMAGE STYLE (high priority, must follow): ${styleText}`);
  parts.push("");
  if (artStyle !== "kidsBook" && hasHeadshot) {
    parts.push(
      `STYLE OVERRIDE (highest priority): The final rendering MUST match the IMAGE STYLE above. The attached reference photo is for IDENTITY/LIKENESS ONLY — do NOT copy its photographic, painterly, or soft textures. Do NOT default to watercolor, children's-book, or storybook rendering. Render strictly in: ${styleText}`
    );
    parts.push("");
  }
  parts.push(
    "TEXT RENDERING RULE (mandatory): Do not render any words, letters, numbers, titles, chapter headings, captions, page numbers, QR codes, watermarks, signs, logos, or any typographic marks anywhere in the image. The output must be pure illustration with zero text."
  );
  if (artStyle === "kidsBook") {
    parts.push(
      "FACIAL DETAIL RULE: Keep eyes expressive and human-like with visible iris/pupil detail and gentle eyelid/eyebrow definition, while preserving the soft watercolor children's-book vibe."
    );
  }
  parts.push("");
  parts.push(`MEMORY TEXT (do not contradict): ${memoryText}`);
  parts.push("");
  if (characters) {
    parts.push("CHARACTER CARDS:");
    parts.push(characters);
    parts.push("");
  }
  parts.push(`NARRATOR PRESENCE HINT: ${narratorPresence}`);
  parts.push("");
  const identityBlock = narratorIdentityPromptSection(narratorPresence, hasHeadshot, job || {});
  if (identityBlock) {
    parts.push("NARRATOR APPEARANCE (likeness policy + profile notes):");
    parts.push(identityBlock);
    parts.push("");
  }
  parts.push(`SCENE SUMMARY: ${sceneDescription}`);
  parts.push("");
  parts.push(`STYLE: ${styleText}`);
  const styleRefHint = styleReferencePromptHint(artStyle, styleReferencePreset);
  if (styleRefHint) {
    parts.push("");
    parts.push(styleRefHint);
  }
  if (narratorPresence !== "likelyAbsent") {
    parts.push("");
    parts.push(
      "NARRATOR REFERENCE IMAGE RULE: If a narrator headshot reference image is attached, use it as the primary visual identity anchor for the narrator whenever the narrator is present or plausibly present in this memory."
    );
    parts.push(
      "NARRATOR IDENTITY RULE: If a narrator reference image is attached, preserve that person's core identity. You may adapt apparent age to fit memory-era cues without changing who the narrator is."
    );
  }
  if (artStyle === "realistic") {
    parts.push("");
    parts.push(
      "Camera pulled back, face partly turned away or softly out of focus so exact features are not discernible. Or another method where the face isn't perfectly clear."
    );
  }
  parts.push("");
  parts.push(`STYLE REMINDER: ${styleText}`);
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
  return null;
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

async function generateIllustrationBuffer(geminiApiKey, prompt, size, referenceImageBuffers) {
  const anti =
    "Do not include any words, letters, numbers, captions, signs, logos, or typographic marks in the image.";
  const lower = prompt.toLowerCase();
  const promptForGeneration =
    lower.includes("do not include any words") ||
    lower.includes("do not render any words") ||
    lower.includes("no text") ||
    lower.includes("do not include text") ||
    lower.includes("text rendering rule")
      ? prompt
      : `${prompt}\n\n${anti}`;

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

  // HTTP 200 path: figure out exactly why we did or did not get an image.
  // Gemini returns 200 even when content was filtered (e.g. SAFETY block) or
  // the model decided not to produce an image — we want to surface that.
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

  const reason =
    blockReason
      ? `blocked: ${blockReason}`
      : finishReason
        ? `finishReason=${finishReason}`
        : "unknown (no image part in response)";
  const detail = textParts ? ` Detail: ${textParts}` : "";
  const err = new Error(`Gemini returned no image (${reason}).${detail}`);
  err.geminiBody = data;
  err.geminiFinishReason = finishReason;
  err.geminiBlockReason = blockReason;
  err.geminiSafetyRatings = safetyRatings;
  err.geminiTextResponse = textParts || null;
  err.noImageBytes = true;
  throw err;
}

async function generateBackCoverPitch(geminiApiKey, prompt) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=${encodeURIComponent(geminiApiKey)}`;
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
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages,
      ...extra
    });
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

  async function extractAge(memoryText) {
    const ex = explicitAge(memoryText);
    if (ex != null) return ex;
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
      const dash = after.indexOf("-");
      if (dash > 0) narratorName = after.slice(0, dash).trim();
    }
    const narratorGuidance = narratorName
      ? `

NARRATOR IDENTITY: The first character listed (${narratorName}) IS the narrator/main character telling this story.
- When the memory says "I", "me", or "my", that refers to ${narratorName}.
- DO NOT say "the narrator and ${narratorName}" - they are the SAME person.
- Use ${narratorName}'s name directly instead of "the narrator".`
      : "";
    const systemPrompt = `You are a visual scene extractor. Extract the key visual moment from this memory.

CRITICAL RULES:
1. **ACCURACY IS PARAMOUNT**: The number of people must match EXACTLY.
   - Example: "Me and 4 roommates" = 5 people total.
   - IMPORTANT: The narrator IS one of the named characters (usually the first one). Do NOT count them twice.
   - If the narrator is "Melody" and the memory says "I and Caleb", that's 2 people (Melody + Caleb), NOT 3.
2. **Identify the Key Scene**: Pick the most important visual moment.
3. **Keep it Simple but Complete**: Describe the setting, who is there, and what they are doing.
4. **No Redundant Descriptions**: Do not describe physical appearance (hair, skin, etc.) as that is handled separately. Just use names.
5. **Direct Style**: Use simple, factual sentences.
6. **Body Position Accuracy**: Preserve the EXACT body positions described in the memory (sitting, standing, laying, kneeling, running, etc.). If the memory says "sitting", the scene MUST describe them sitting. If "laying down", they MUST be laying down. Never change or omit described postures.
${narratorGuidance}
${characterGuidance}

Output: One paragraph describing the scene action and participants accurately.`;
    const scene = await chatMini(
      [
        { role: "system", content: systemPrompt },
        { role: "user", content: rawText }
      ],
      { temperature: 0.1 }
    );
    return String(scene || rawText).trim() || rawText;
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
    COVER_STYLE_BINDING,
    isQuestionDrivenMemory
  };
}

module.exports = {
  createStorybookAI,
  inferNarratorPresence,
  buildCharacterContextFromDetails,
  buildCharacterList,
  assembleFinalPrompt,
  generateIllustrationBuffer,
  loadStyleReferencePng,
  isQuestionDrivenMemory
};

