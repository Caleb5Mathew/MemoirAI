/**
 * Server-side AI proxy callables. The iOS client never holds OpenAI/Gemini API keys —
 * it calls these onCall functions, which validate input, enforce a per-user daily quota,
 * and make the upstream request with secrets injected server-side.
 */

const crypto = require("crypto");
const OpenAI = require("openai");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const {
  generateIllustrationBufferGuarded,
  editImageWithGemini,
  uploadPngWithDownloadURL,
  buildCoverIllustrationPrompt,
  buildBackCoverIllustrationPrompt
} = require("./storybookAI");

const openaiSecret = defineSecret("OPENAI_API_KEY");
const geminiSecret = defineSecret("GEMINI_API_KEY");

function firestore() {
  return admin.firestore();
}

/** When false (default), callables accept requests without an App Check token. Set ENFORCE_APP_CHECK=true once the iOS App Check SDK has shipped. */
function isAppCheckEnforced() {
  return String(process.env.ENFORCE_APP_CHECK || "").trim().toLowerCase() === "true";
}

const CHAT_DAILY_LIMIT = 200;
const IMAGE_DAILY_LIMIT = 100;

const OPENAI_CHAT_MODELS = new Set(["gpt-5-mini", "gpt-5-nano"]);
const GEMINI_CHAT_MODELS = new Set(["gemini-2.5-flash"]);

// Older app builds still name retired models; serve them with the current equivalent
// so a model swap never requires an App Store release.
const CHAT_MODEL_ALIASES = {
  "gpt-4o-mini": "gpt-5-mini",
  "gpt-4o": "gpt-5-mini",
  "gemini-2.0-flash-exp": "gemini-2.5-flash"
};

const MAX_TOKENS_CAP = 1500;
const MAX_MESSAGE_CHARS_TOTAL = 20000;
const MAX_IMAGES = 4;
const MAX_CHAT_IMAGE_DECODED_BYTES = 8 * 1024 * 1024;

// GeminiImageService.Model — aiEditImage may target either Gemini image model the iOS app uses.
const EDIT_IMAGE_MODELS = new Set(["gemini-3-pro-image-preview", "gemini-2.5-flash-image"]);
const DEFAULT_EDIT_MODEL = "gemini-3-pro-image-preview";
const MAX_EDIT_INSTRUCTION_CHARS = 4000;
const MAX_INPUT_IMAGE_DECODED_BYTES = 20 * 1024 * 1024;

/**
 * Firestore-transaction daily quota counter at `users/{uid}/aiUsage/{bucket}_{YYYY-MM-DD}`.
 * Throws resource-exhausted once `dailyLimit` is reached for the given bucket/day.
 */
async function checkAndIncrementQuota(uid, bucket, dailyLimit) {
  const dayKey = new Date().toISOString().slice(0, 10);
  const ref = firestore().collection("users").doc(uid).collection("aiUsage").doc(`${bucket}_${dayKey}`);
  await firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? Number(snap.data().count || 0) : 0;
    if (current >= dailyLimit) {
      throw new HttpsError("resource-exhausted", "Daily AI usage limit reached. Try again tomorrow.");
    }
    tx.set(
      ref,
      {
        bucket,
        count: current + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );
  });
}

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  return request.auth.uid;
}

/** Rough base64 -> decoded byte size without allocating a Buffer. */
function decodedByteLength(base64) {
  const s = String(base64 || "");
  const padding = s.endsWith("==") ? 2 : s.endsWith("=") ? 1 : 0;
  return Math.floor((s.length * 3) / 4) - padding;
}

function decodeBase64Image(value, fieldName) {
  const s = String(value || "").trim();
  if (!s) throw new HttpsError("invalid-argument", `${fieldName} is required.`);
  if (decodedByteLength(s) > MAX_INPUT_IMAGE_DECODED_BYTES) {
    throw new HttpsError("invalid-argument", `${fieldName} exceeds the ${MAX_INPUT_IMAGE_DECODED_BYTES} byte limit.`);
  }
  let buf;
  try {
    buf = Buffer.from(s, "base64");
  } catch (_) {
    throw new HttpsError("invalid-argument", `${fieldName} is not valid base64.`);
  }
  if (!buf.length) {
    throw new HttpsError("invalid-argument", `${fieldName} decoded to an empty image.`);
  }
  return buf;
}

// --- aiChatCompletion -------------------------------------------------------

function validateChatMessages(rawMessages) {
  if (!Array.isArray(rawMessages) || rawMessages.length === 0) {
    throw new HttpsError("invalid-argument", "messages[] is required.");
  }
  const messages = rawMessages.map((m, i) => {
    const role = m && m.role;
    if (role !== "system" && role !== "user" && role !== "assistant") {
      throw new HttpsError("invalid-argument", `messages[${i}].role must be "system", "user", or "assistant".`);
    }
    const content = m && typeof m.content === "string" ? m.content : "";
    if (!content.trim()) {
      throw new HttpsError("invalid-argument", `messages[${i}].content must be a non-empty string.`);
    }
    return { role, content };
  });
  const totalChars = messages.reduce((sum, m) => sum + m.content.length, 0);
  if (totalChars > MAX_MESSAGE_CHARS_TOTAL) {
    throw new HttpsError("invalid-argument", `messages[] exceed the ${MAX_MESSAGE_CHARS_TOTAL} total character limit.`);
  }
  return messages;
}

function validateChatImages(rawImages, provider) {
  const images = Array.isArray(rawImages) ? rawImages : [];
  if (!images.length) return [];
  if (images.length > MAX_IMAGES) {
    throw new HttpsError("invalid-argument", `A maximum of ${MAX_IMAGES} images is allowed.`);
  }
  if (provider !== "openai") {
    throw new HttpsError("invalid-argument", "images are only supported with provider \"openai\".");
  }
  return images.map((img, i) => {
    const base64 = img && typeof img.base64 === "string" ? img.base64.trim() : "";
    const mimeType = img && typeof img.mimeType === "string" ? img.mimeType.trim() : "";
    if (!base64 || !mimeType) {
      throw new HttpsError("invalid-argument", `images[${i}] must include base64 and mimeType.`);
    }
    if (decodedByteLength(base64) > MAX_CHAT_IMAGE_DECODED_BYTES) {
      throw new HttpsError("invalid-argument", `images[${i}] exceeds the ${MAX_CHAT_IMAGE_DECODED_BYTES} byte limit.`);
    }
    return { base64, mimeType };
  });
}

/** Appends image_url parts (data: URIs) to the last user message, OpenAI vision format. */
function attachImagesToLastUserMessage(messages, images) {
  if (!images.length) return messages;
  let lastUserIdx = -1;
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    if (messages[i].role === "user") {
      lastUserIdx = i;
      break;
    }
  }
  if (lastUserIdx === -1) {
    throw new HttpsError("invalid-argument", "images requires at least one user message.");
  }
  return messages.map((m, i) => {
    if (i !== lastUserIdx) return m;
    const parts = [{ type: "text", text: m.content }];
    for (const img of images) {
      parts.push({ type: "image_url", image_url: { url: `data:${img.mimeType};base64,${img.base64}` } });
    }
    return { role: m.role, content: parts };
  });
}

async function callOpenAiChat({ apiKey, model, messages, temperature, maxTokens, responseFormat }) {
  const openai = new OpenAI({ apiKey });
  const extra = {};
  if (responseFormat === "json") extra.response_format = { type: "json_object" };
  const isGpt5Family = model.startsWith("gpt-5");
  if (isGpt5Family) {
    // gpt-5 models reject max_tokens and non-default temperature, and spend reasoning
    // tokens from the completion budget — floor the cap so tiny limits still yield text.
    extra.max_completion_tokens = Math.max(maxTokens, 128);
    extra.reasoning_effort = "minimal";
  } else {
    extra.max_tokens = maxTokens;
    if (typeof temperature === "number") extra.temperature = temperature;
  }
  let completion;
  try {
    completion = await openai.chat.completions.create({
      model,
      messages,
      ...extra
    });
  } catch (e) {
    console.error("aiChatCompletion openai upstream error", String(e?.message || e));
    throw new HttpsError("internal", "Upstream AI provider request failed.");
  }
  const choice = (completion.choices && completion.choices[0]) || {};
  const usage = completion.usage || {};
  return {
    text: choice.message?.content || "",
    usage: {
      inputTokens: usage.prompt_tokens || 0,
      outputTokens: usage.completion_tokens || 0
    },
    model: completion.model || model
  };
}

/** Maps the request's chat messages onto Gemini's systemInstruction + multi-turn contents shape. */
function buildGeminiChatContents(messages) {
  const systemText = messages
    .filter((m) => m.role === "system")
    .map((m) => m.content)
    .join("\n\n");
  const contents = messages
    .filter((m) => m.role !== "system")
    .map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }]
    }));
  return {
    systemInstruction: systemText ? { parts: [{ text: systemText }] } : undefined,
    contents
  };
}

async function callGeminiChat({ apiKey, model, messages, temperature, maxTokens, responseFormat }) {
  const { systemInstruction, contents } = buildGeminiChatContents(messages);
  const generationConfig = {
    temperature: typeof temperature === "number" ? temperature : 0.7,
    maxOutputTokens: maxTokens
  };
  if (responseFormat === "json") generationConfig.responseMimeType = "application/json";
  const body = { contents, generationConfig };
  if (systemInstruction) body.systemInstruction = systemInstruction;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`;
  let res;
  let data;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(55000)
    });
    data = await res.json().catch(() => ({}));
  } catch (e) {
    console.error("aiChatCompletion gemini network error", String(e?.message || e));
    throw new HttpsError("internal", "Upstream AI provider request failed.");
  }
  if (!res.ok) {
    const apiMsg = (data && data.error && data.error.message) || `HTTP ${res.status}`;
    console.error("aiChatCompletion gemini upstream error", res.status, apiMsg);
    throw new HttpsError("internal", "Upstream AI provider request failed.");
  }

  const text = data.candidates?.[0]?.content?.parts?.[0]?.text || "";
  const usage = data.usageMetadata || {};
  return {
    text: String(text).trim(),
    usage: {
      inputTokens: usage.promptTokenCount || 0,
      outputTokens: usage.candidatesTokenCount || 0
    },
    model
  };
}

exports.aiChatCompletion = onCall(
  {
    secrets: [openaiSecret, geminiSecret],
    timeoutSeconds: 60,
    memory: "256MiB",
    region: "us-central1",
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    const uid = requireAuth(request);
    const body = request.data || {};

    let provider;
    if (body.provider === undefined || body.provider === null || body.provider === "openai") {
      provider = "openai";
    } else if (body.provider === "gemini") {
      provider = "gemini";
    } else {
      throw new HttpsError("invalid-argument", 'provider must be "openai" or "gemini".');
    }

    const requestedModel = String(body.model || "").trim();
    const model = CHAT_MODEL_ALIASES[requestedModel] || requestedModel;
    const allowedModels = provider === "openai" ? OPENAI_CHAT_MODELS : GEMINI_CHAT_MODELS;
    if (!allowedModels.has(model)) {
      throw new HttpsError("invalid-argument", `Unsupported model "${requestedModel}" for provider "${provider}".`);
    }

    const messages = validateChatMessages(body.messages);
    const images = validateChatImages(body.images, provider);

    let maxTokens = Number(body.maxTokens);
    if (!Number.isFinite(maxTokens) || maxTokens <= 0) maxTokens = MAX_TOKENS_CAP;
    maxTokens = Math.min(Math.floor(maxTokens), MAX_TOKENS_CAP);

    let temperature;
    if (body.temperature !== undefined && body.temperature !== null) {
      const t = Number(body.temperature);
      if (!Number.isFinite(t) || t < 0 || t > 2) {
        throw new HttpsError("invalid-argument", "temperature must be a number between 0 and 2.");
      }
      temperature = t;
    }

    const responseFormat = body.responseFormat === "json" ? "json" : "text";

    await checkAndIncrementQuota(uid, "chat", CHAT_DAILY_LIMIT);

    if (provider === "openai") {
      const apiKey = String(openaiSecret.value() || "").trim();
      if (!apiKey) throw new HttpsError("internal", "AI provider is not configured.");
      const openaiMessages = attachImagesToLastUserMessage(messages, images);
      return callOpenAiChat({ apiKey, model, messages: openaiMessages, temperature, maxTokens, responseFormat });
    }

    const apiKey = String(geminiSecret.value() || "").trim();
    if (!apiKey) throw new HttpsError("internal", "AI provider is not configured.");
    return callGeminiChat({ apiKey, model, messages, temperature, maxTokens, responseFormat });
  }
);

// --- aiGenerateCoverArt ------------------------------------------------------

exports.aiGenerateCoverArt = onCall(
  {
    secrets: [geminiSecret],
    timeoutSeconds: 300,
    memory: "1GiB",
    region: "us-central1",
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    const uid = requireAuth(request);
    const body = request.data || {};

    let kind;
    if (body.kind === "front" || body.kind === "back") {
      kind = body.kind;
    } else {
      throw new HttpsError("invalid-argument", 'kind must be "front" or "back".');
    }

    const profileName = String(body.profileName || "").trim();
    if (!profileName) {
      throw new HttpsError("invalid-argument", "profileName is required.");
    }

    let frontCoverArtBuf = null;
    if (kind === "back") {
      if (!body.frontCoverArtBase64 || !String(body.frontCoverArtBase64).trim()) {
        throw new HttpsError("invalid-argument", 'frontCoverArtBase64 is required when kind is "back".');
      }
      frontCoverArtBuf = decodeBase64Image(body.frontCoverArtBase64, "frontCoverArtBase64");
    }

    const headshotBuf = body.headshotBase64 ? decodeBase64Image(body.headshotBase64, "headshotBase64") : null;
    const memoryThemes = Array.isArray(body.memoryThemes) ? body.memoryThemes.map((t) => String(t || "")) : [];

    await checkAndIncrementQuota(uid, "image", IMAGE_DAILY_LIMIT);

    const apiKey = String(geminiSecret.value() || "").trim();
    if (!apiKey) throw new HttpsError("internal", "AI provider is not configured.");

    const promptArgs = {
      hasHeadshot: !!headshotBuf,
      ethnicity: body.ethnicity,
      gender: body.gender,
      memoryThemes,
      artStyle: body.artStyle,
      customStyle: body.customStyle
    };
    const prompt =
      kind === "front"
        ? buildCoverIllustrationPrompt({
            ...promptArgs,
            profileName,
            printTitle: body.printTitle,
            protagonistCanonLine: body.protagonistCanonLine
          })
        : buildBackCoverIllustrationPrompt(promptArgs);

    const refs =
      kind === "front"
        ? headshotBuf
          ? [headshotBuf]
          : []
        : headshotBuf
          ? [frontCoverArtBuf, headshotBuf]
          : [frontCoverArtBuf];

    let imageBuf;
    try {
      imageBuf = await generateIllustrationBufferGuarded(apiKey, prompt, "5:4", refs, (event, details) =>
        console.log(event, { uid, kind, ...details })
      );
    } catch (e) {
      console.error("aiGenerateCoverArt generation failed", { uid, kind, message: String(e?.message || e) });
      throw new HttpsError("internal", "Cover art generation failed. Please try again.");
    }

    const storagePath = `users/${uid}/aiCoverArt/${crypto.randomUUID()}.png`;
    try {
      return await uploadPngWithDownloadURL(storagePath, imageBuf);
    } catch (e) {
      console.error("aiGenerateCoverArt upload failed", { uid, kind, message: String(e?.message || e) });
      throw new HttpsError("internal", "Cover art upload failed. Please try again.");
    }
  }
);

// --- aiEditImage -------------------------------------------------------------

exports.aiEditImage = onCall(
  {
    secrets: [geminiSecret],
    timeoutSeconds: 240,
    memory: "1GiB",
    region: "us-central1",
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    const uid = requireAuth(request);
    const body = request.data || {};

    const editInstruction = String(body.editInstruction || "").trim();
    if (!editInstruction) {
      throw new HttpsError("invalid-argument", "editInstruction is required.");
    }
    if (editInstruction.length > MAX_EDIT_INSTRUCTION_CHARS) {
      throw new HttpsError("invalid-argument", `editInstruction exceeds the ${MAX_EDIT_INSTRUCTION_CHARS} character limit.`);
    }

    const model = body.model ? String(body.model).trim() : DEFAULT_EDIT_MODEL;
    if (!EDIT_IMAGE_MODELS.has(model)) {
      throw new HttpsError("invalid-argument", `Unsupported model "${model}".`);
    }

    const size = body.size ? String(body.size).trim() : "1792x1024";
    const imageBuffer = decodeBase64Image(body.imageBase64, "imageBase64");
    const styleAnchorBuffer = body.styleAnchorBase64 ? decodeBase64Image(body.styleAnchorBase64, "styleAnchorBase64") : null;

    await checkAndIncrementQuota(uid, "image", IMAGE_DAILY_LIMIT);

    const apiKey = String(geminiSecret.value() || "").trim();
    if (!apiKey) throw new HttpsError("internal", "AI provider is not configured.");

    let imageBuf;
    try {
      imageBuf = await editImageWithGemini(apiKey, {
        model,
        editInstruction,
        size,
        imageBuffer,
        styleAnchorBuffer
      });
    } catch (e) {
      console.error("aiEditImage generation failed", { uid, model, message: String(e?.message || e) });
      throw new HttpsError("internal", "Image edit failed. Please try again.");
    }

    const storagePath = `users/${uid}/aiEdits/${crypto.randomUUID()}.png`;
    try {
      return await uploadPngWithDownloadURL(storagePath, imageBuf);
    } catch (e) {
      console.error("aiEditImage upload failed", { uid, message: String(e?.message || e) });
      throw new HttpsError("internal", "Image edit upload failed. Please try again.");
    }
  }
);
