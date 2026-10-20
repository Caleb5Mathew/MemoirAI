const pLimit = require("p-limit");
const { safeErrorMetadata } = require("./privacyLogging");

const TRANSCRIPTION_REFINEMENT_VERSION = 2;
const TRANSCRIPTION_REFINEMENT_MODEL = "gpt-5-mini";
const TRANSCRIPTION_REFINEMENT_CHUNK_CHARS = 6500;
const TRANSCRIPT_FILLERS = new Set(["um", "uh", "erm"]);
const TRANSCRIPT_STUTTER_WORDS = new Set([
  "i", "we", "he", "she", "they", "it", "the", "a", "an", "to", "my", "your", "our"
]);

function transcriptWords(text) {
  return Array.from(String(text || "").matchAll(/[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/gu), (match) => ({
    original: match[0],
    value: match[0].toLocaleLowerCase("en-US"),
    start: match.index,
    end: match.index + match[0].length
  }));
}

function orderedTranscriptWordIndexes(rawText, refinedText) {
  const raw = transcriptWords(rawText);
  const refined = transcriptWords(refinedText);
  const keptRawIndexes = [];
  let rawIndex = 0;

  for (const word of refined) {
    while (rawIndex < raw.length && raw[rawIndex].value !== word.value) rawIndex += 1;
    if (rawIndex >= raw.length) return null;
    keptRawIndexes.push(rawIndex);
    rawIndex += 1;
  }
  return keptRawIndexes;
}

function validateTranscriptRefinement(rawText, refinedText) {
  const source = String(rawText || "");
  const raw = transcriptWords(rawText);
  const refined = transcriptWords(refinedText);
  const keptRawIndexes = orderedTranscriptWordIndexes(rawText, refinedText);
  if (!keptRawIndexes) return false;

  const kept = new Set(keptRawIndexes);
  for (let index = 0; index < raw.length; index += 1) {
    if (kept.has(index)) continue;
    const word = raw[index].value;
    const isUppercaseInitialism = /^[A-Z]{2,}$/.test(raw[index].original);
    const before = source.slice(raw[index - 1]?.end ?? 0, raw[index].start);
    const after = source.slice(raw[index].end, raw[index + 1]?.start ?? source.length);
    const commaBefore = /,\s*$/.test(before);
    const commaAfter = /^\s*,/.test(after);
    const sentenceOrQuoteStart = index === 0 || /(?:[.!?]\s+|[“"'])\s*$/.test(before);
    const sentenceEnd = /^\s*[.!?]/.test(after);
    const isDelimitedFiller = TRANSCRIPT_FILLERS.has(word) && !isUppercaseInitialism &&
      ((commaBefore && (commaAfter || sentenceEnd)) || (commaAfter && sentenceOrQuoteStart));
    if (isDelimitedFiller) continue;
    const repeatsNeighbor = raw[index - 1]?.value === word || raw[index + 1]?.value === word;
    const neighborSeparator = raw[index - 1]?.value === word ? before : after;
    const isExplicitStutter = TRANSCRIPT_STUTTER_WORDS.has(word) && repeatsNeighbor && /^\s*[-—]\s*$/.test(neighborSeparator);
    if (isExplicitStutter) continue;
    return false;
  }
  return refined.length > 0;
}

function protectedTranscriptWordIndexes(rawText, glossary = []) {
  const raw = transcriptWords(rawText);
  const protectedIndexes = new Set();
  const protectedWords = new Set([
    "no", "not", "never", "neither", "nor", "without", "cannot", "can't", "couldn't", "didn't",
    "doesn't", "don't", "hadn't", "hasn't", "haven't", "isn't", "wasn't", "weren't", "won't", "wouldn't",
    "maybe", "perhaps", "probably", "possibly", "around", "about", "approximately", "think", "thought",
    "remember", "believe", "guess", "unsure", "uncertain",
    "mother", "father", "mom", "mum", "dad", "brother", "sister", "son", "daughter", "husband", "wife",
    "grandmother", "grandfather", "grandma", "grandpa", "aunt", "uncle", "cousin"
  ]);
  const glossaryWords = new Set(glossary.flatMap((term) => transcriptWords(term).map((word) => word.value)));
  raw.forEach((word, index) => {
    const before = String(rawText || "").slice(raw[index - 1]?.end ?? 0, word.start);
    const beginsSentence = index === 0 || /[.!?][\s“"']*$/.test(before);
    const looksLikeName = /^\p{Lu}[\p{L}'’]*$/u.test(word.original) && !beginsSentence;
    if (/\p{N}/u.test(word.original) || protectedWords.has(word.value) || glossaryWords.has(word.value) || looksLikeName) {
      protectedIndexes.add(index);
    }
  });
  return protectedIndexes;
}

function validateSemanticTranscriptRefinement(rawText, refinedText, glossary = []) {
  const raw = transcriptWords(rawText);
  const refined = transcriptWords(refinedText);
  if (!raw.length || !refined.length) return false;
  const keptIndexes = orderedTranscriptWordIndexes(rawText, refinedText);
  if (!keptIndexes) return false;
  const kept = new Set(keptIndexes);
  for (const index of protectedTranscriptWordIndexes(rawText, glossary)) {
    if (!kept.has(index)) return false;
  }
  const deletedCount = raw.length - refined.length;
  const maximumDeletion = Math.max(12, Math.floor(raw.length * 0.3));
  return deletedCount <= maximumDeletion;
}

function splitTranscriptForRefinement(rawText, maximumCharacters = TRANSCRIPTION_REFINEMENT_CHUNK_CHARS) {
  const source = String(rawText || "").trim();
  if (!source) return [];
  const chunks = [];
  let remaining = source;
  while (remaining.length > maximumCharacters) {
    const window = remaining.slice(0, maximumCharacters + 1);
    const minimumBreak = Math.floor(maximumCharacters * 0.55);
    const sentenceBreaks = [...window.matchAll(/[.!?][”'\"]?(?:\s+|$)/g)]
      .map((match) => match.index + match[0].length)
      .filter((index) => index >= minimumBreak && index <= maximumCharacters);
    const whitespaceBreak = window.lastIndexOf(" ", maximumCharacters);
    const splitAt = sentenceBreaks.at(-1) || (whitespaceBreak >= minimumBreak ? whitespaceBreak + 1 : maximumCharacters);
    chunks.push(remaining.slice(0, splitAt).trim());
    remaining = remaining.slice(splitAt).trim();
  }
  if (remaining) chunks.push(remaining);
  return chunks;
}

function transcriptionRefinementMessages(rawText, language, glossary) {
  const protectedTerms = glossary.length ? `\nProtected names and terms: ${glossary.join(", ")}` : "";
  return [
    {
      role: "system",
      content: `You are a conservative memoir copy editor. Make spoken recollections clear and pleasant to read as a book while preserving the speaker's story and voice. Remove verbal fillers such as um, uh, like, and you know only when they are fillers. Remove abandoned false starts and accidental repetition. Fix punctuation, capitalization, and paragraph breaks. Use only words already present in the transcript and keep them in their original order. Never add, substitute, summarize, reorder, or rewrite words. Preserve every fact, name, number, date, relationship, negation, uncertainty, correction, dialect choice, profanity, meaningful repetition, and quoted speech. Return JSON only: {"text":"..."}.`
    },
    {
      role: "user",
      content: `Language: ${language || "en"}.${protectedTerms}\n\nTranscript:\n${rawText}`
    }
  ];
}

async function refineTranscriptWithOpenAI({
  apiKey,
  rawText,
  language = "en",
  glossary = [],
  callChat
}) {
  const raw = String(rawText || "").trim();
  if (!raw) return { text: "", model: "deterministic-fallback" };
  const chunks = splitTranscriptForRefinement(raw);
  const limit = pLimit(3);
  try {
    const refinedChunks = await Promise.all(chunks.map((chunk) => limit(async () => {
      const response = await callChat({
        apiKey,
        model: TRANSCRIPTION_REFINEMENT_MODEL,
        messages: transcriptionRefinementMessages(chunk, language, glossary),
        maxTokens: 2200,
        responseFormat: "json"
      });
      const parsed = JSON.parse(String(response.text || ""));
      const candidate = String(parsed.text || "").trim();
      if (!validateSemanticTranscriptRefinement(chunk, candidate, glossary)) {
        throw new Error("Transcript refinement changed protected content.");
      }
      return addTranscriptParagraphs(candidate);
    })));
    const text = refinedChunks.join("\n\n").trim();
    if (!validateSemanticTranscriptRefinement(raw, text, glossary)) {
      throw new Error("Combined transcript refinement failed validation.");
    }
    return { text, model: TRANSCRIPTION_REFINEMENT_MODEL };
  } catch (error) {
    console.error("transcript refinement fallback", safeErrorMetadata(error));
    return { text: refineTranscriptForReading(raw, language), model: "deterministic-fallback" };
  }
}

function addTranscriptParagraphs(text, targetLength = 700) {
  const paragraphs = String(text || "").split(/\n{2,}/).map((paragraph) => paragraph.trim()).filter(Boolean);
  const formatted = [];
  for (const paragraph of paragraphs) {
    const sentences = paragraph.match(/[^.!?]+(?:[.!?]+[”'\"]?|$)/g) || [paragraph];
    let current = "";
    for (const sentenceValue of sentences) {
      const sentence = sentenceValue.trim();
      if (!sentence) continue;
      if (current && current.length + sentence.length + 1 > targetLength) {
        formatted.push(current);
        current = sentence;
      } else {
        current = current ? `${current} ${sentence}` : sentence;
      }
    }
    if (current) formatted.push(current);
  }
  return formatted.join("\n\n");
}

function refineTranscriptForReading(rawText, language = "en") {
  const raw = String(rawText || "").trim();
  if (!raw) return "";

  let refined = raw;
  if (String(language || "").toLowerCase() === "en") {
    refined = refined
      .replace(/,\s*\b(um+|uh+|erm+)\b\s*,\s*/giu, (match, filler) =>
        /^[A-Z]{2,}$/.test(filler) ? match : " ")
      .replace(/(^|[.!?]\s+|[“"'])\b(um+|uh+|erm+)\b,\s*/giu, (match, prefix, filler) =>
        /^[A-Z]{2,}$/.test(filler) ? match : prefix)
      .replace(/,\s*\b(um+|uh+|erm+)\b(?=\s*[.!?])/giu, (match, filler) =>
        /^[A-Z]{2,}$/.test(filler) ? match : "")
      .replace(/\b(i|we|he|she|they|it|the|a|an|to|my|your|our)\s*[-—]\s*\1\b/giu, "$1")
      .replace(/[ \t]+([,.;:!?])/g, "$1")
      .replace(/,\s*,+/g, ",")
      .replace(/,\s*([.!?])/g, "$1")
      .replace(/([([{“])\s+/g, "$1")
      .replace(/[ \t]{2,}/g, " ")
      .replace(/^\s*[,;:—-]+\s*/gm, "")
      .replace(/\n[ \t]+/g, "\n")
      .trim();
  }
  refined = addTranscriptParagraphs(refined);

  return validateTranscriptRefinement(raw, refined) ? refined : raw;
}

module.exports = { TRANSCRIPTION_REFINEMENT_VERSION, transcriptWords, orderedTranscriptWordIndexes, validateTranscriptRefinement, validateSemanticTranscriptRefinement, splitTranscriptForRefinement, transcriptionRefinementMessages, refineTranscriptWithOpenAI, refineTranscriptForReading };
