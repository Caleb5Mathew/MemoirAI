const admin = require("firebase-admin");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { buildFastOnboardingIllustrationPrompt } = require("./onboardingIllustrationPolicy");
const OpenAI = require("openai");
const { refineTranscriptWithOpenAI, refineTranscriptForReading, TRANSCRIPTION_REFINEMENT_VERSION } = require("./transcriptReadingCopy");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const {
  generateIllustrationBuffer,
  createStorybookAI,
  GEMINI_IMAGE_MODEL,
  artStyleMemoryIllustrationStyleDescription,
  loadStyleReferencePng,
  mimeTypeForImageBuffer
} = require("./storybookAI");
const { PROVIDER_PERSIST_RESERVE_MS } = require("./retryDeadlinePolicy");
const ONBOARDING_TITLE_WINDOW_MS = 15_000 + PROVIDER_PERSIST_RESERVE_MS;
const { assertAccountNotDeleting } = require("./accountStateGuards");
const { safeErrorMetadata, safeLogIdentifier } = require("./privacyLogging");

const geminiSecret = defineSecret("GEMINI_API_KEY");
const openaiSecret = defineSecret("OPENAI_API_KEY");
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const JOB_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const MAX_STORY_CHARACTERS = 12_000;
const MAX_PROFILE_NAME_CHARACTERS = 100;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const ONBOARDING_IMAGE_MODEL = GEMINI_IMAGE_MODEL;
const FAST_ONBOARDING_IMAGE_MODEL = "gemini-3.1-flash-lite-image";
const fastStyleReference = fs.readFileSync(path.join(__dirname, "assets/style/Refnormal-onboarding.jpg"));
const ONBOARDING_PREVIEW_VERSION = 1;
const STALE_GENERATION_MS = 2 * 60 * 1000;
const MAX_GENERATION_ATTEMPTS = 3;

function secretReader(secret) {
  return () => secret.value();
}

function isAppCheckEnforced() {
  return String(process.env.ENFORCE_APP_CHECK || "").toLowerCase() === "true";
}

function normalizeText(value, maximum, field) {
  const text = String(value || "").trim().replace(/\s+/g, " ");
  if (!text || text.length > maximum || /[<>\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(text)) {
    throw new Error(`invalid ${field}`);
  }
  return text;
}

function sanitizeOnboardingPreviewRequest(input, userId) {
  const requestId = String(input?.requestId || "").trim();
  const profileId = String(input?.profileId || "").trim().toLowerCase();
  const memoryId = String(input?.memoryId || "").trim().toLowerCase();
  if (!JOB_ID_PATTERN.test(requestId)) throw new Error("invalid requestId");
  if (!UUID_PATTERN.test(profileId)) throw new Error("invalid profileId");
  if (!UUID_PATTERN.test(memoryId)) throw new Error("invalid memoryId");
  const expectedPhotoPath = `users/${userId}/profiles/${profileId}/subjectPhoto.jpg`;
  const photoPath = String(input?.subjectPhotoStoragePath || "").trim();
  const previewPhotoPath = `users/${userId}/onboardingPreviews/${requestId}/subjectPhoto.jpg`;
  if (photoPath && photoPath !== expectedPhotoPath && photoPath !== previewPhotoPath) {
    throw new Error("invalid subjectPhotoStoragePath");
  }
  const storytellerRole = input?.storytellerRole ?? "subject";
  if (!["subject", "helper"].includes(storytellerRole)) throw new Error("invalid storytellerRole");
  return {
    storytellerRole,
    requestId,
    profileId,
    memoryId,
    profileName: normalizeText(input?.profileName, MAX_PROFILE_NAME_CHARACTERS, "profileName"),
    storyText: normalizeText(input?.storyText, MAX_STORY_CHARACTERS, "storyText"),
    subjectPhotoStoragePath: photoPath || null
  };
}

function onboardingPreviewRequestHash(value) {
  return crypto.createHash("sha256").update(JSON.stringify({
    version: ONBOARDING_PREVIEW_VERSION,
    profileId: value.profileId,
    memoryId: value.memoryId,
    profileName: value.profileName,
    storyText: value.storyText,
    ...(value.storytellerRole === "helper" ? { storytellerRole: "helper" } : {}),
    subjectPhotoStoragePath: value.subjectPhotoStoragePath
  })).digest("hex");
}

function onboardingAgeDirection() {
  return `HISTORICAL AGE LOCK: This question asks for a childhood memory. Read the memory for the book subject's age at the time: an explicitly stated age or clear life stage overrides this default. If no age is stated and no contrary life-stage evidence exists, depict the book subject as a school-age child, approximately 6–12, using the setting and activities to choose a plausible appearance. This range is only a visual casting assumption, never a biographical fact to add to the story. A current elderly headshot is identity reference, not scene-age reference: do not copy gray hair, wrinkles, facial hair, adult height, or elderly posture onto the child. Preserve recognizable skin tone and age-appropriate facial identity. If the story explicitly concerns adulthood, depict that stated period instead. Do not infer an exact year, location, or historical event absent from the memory.`;
}

function buildOnboardingIllustrationPrompt({ profileName, storyText, hasHeadshot, hasStyleReference = false, storytellerRole = "subject" }) {
  const perspective = storytellerRole === "helper"
    ? `A helper is telling this story about ${profileName}. The helper and ${profileName} are different people. First-person words such as "I" and "my" refer to the helper unless the transcript explicitly quotes ${profileName}. Resolve relationships from the actual wording: if the helper says "my dad played in fields as a boy", the father is the book subject, not an additional adult father beside a child with the helper's identity. Never assume the speaking helper's first-person self is the person in the headshot. Do not add the helper to the scene unless the story places them there. Preserve the original narrative perspective; do not convert a helper's account into invented first-person memories.`
    : `${profileName} is telling their own memory. First-person recollections refer to ${profileName} unless explicitly quoted from another person.`;
  const identity = hasHeadshot
    ? `The attached portrait shows ${profileName}, the book subject, as they look today. If the memory places ${profileName} at a younger age, the child or younger person is ${profileName} re-aged from this portrait. Preserve stable facial identity, skin tone, ethnic features, eye shape, and core face proportions while changing age-appropriate features. Every parent, friend, spouse, child, and other person distinct from ${profileName} is a different individual and MUST NOT copy the portrait's face, hair, facial hair, or clothing. Never render present-day ${profileName} as an extra adult or a second copy.`
    : `The book subject is ${profileName}. Render this person only when the memory places them visibly in the scene.`;
  const style = artStyleMemoryIllustrationStyleDescription("kidsBook");
  const references = [
    hasStyleReference ? "REFERENCE IMAGE #1 is the children's-book STYLE ANCHOR. Match its watercolor medium, loose ink linework, visible paper texture, simplified expressive faces, and warm palette. Copy only the illustration style, not its people, objects, or composition." : "Enforce the watercolor children's-book style from the text even without a style image.",
    hasHeadshot ? `REFERENCE IMAGE #${hasStyleReference ? 2 : 1} is the book subject's IDENTITY ONLY. Do NOT copy photographic lighting, skin texture, exposure, lens look, or realistic rendering. Re-render the person completely in the children's-book STYLE LOCK.` : "No identity portrait is attached."
  ].join("\n");
  return `STYLE LOCK (same as the normal printed book):\n${style}\n\n${references}\n\nROLE LOCK — READ BEFORE ANY REFERENCE IMAGE:\n${perspective}\n${identity}\n\n${onboardingAgeDirection()}\n\nMEMORY ABOUT ${profileName.toUpperCase()}:\n${storyText}\n\nCreate one wordless 4:3 landscape illustration for a premium printed memoir. Choose the single clearest visual moment. Render a soft watercolor children’s-book scene, with loose hand-drawn ink, visibly painted paper, simplified shapes, and stylized expressive faces. Keep the scene readable and the action physically coherent. Do not turn this into a realistic oil painting, cinematic render, or detailed digital portrait. Preserve the exact action, setting, people count, and relationships in the memory. The attached portrait is identity reference only and must never appear as a photo, frame, inset, thumbnail, prop, or second copy of the book subject. No words, letters, captions, speech bubbles, logos, signatures, watermarks, QR codes, borders, or page furniture.`;
}

function previewTitle(storyText, storytellerRole = "subject") {
  const text = String(storyText || "").toLowerCase();
  if (text.includes("radio")) return "The old radio";
  if (text.includes("bicycle") || text.includes("bike")) return "The bicycle";
  if (text.includes("beach") || text.includes("ocean")) return "By the water";
  if (text.includes("school")) return "A school-day memory";
  return storytellerRole === "helper" ? "A memory to keep" : "A memory I carry";
}

async function loadOwnedSubjectPhoto({ bucket, userId, profileId, requestId, storagePath }) {
  if (!storagePath) return null;
  const expected = `users/${userId}/profiles/${profileId}/subjectPhoto.jpg`;
  const previewPhotoPath = `users/${userId}/onboardingPreviews/${requestId}/subjectPhoto.jpg`;
  if (storagePath !== expected && (!JOB_ID_PATTERN.test(String(requestId || "")) || storagePath !== previewPhotoPath)) {
    throw new HttpsError("invalid-argument", "Invalid profile photo path.");
  }
  const file = bucket.file(storagePath);
  const [metadata] = await file.getMetadata();
  const contentType = String(metadata?.contentType || "").split(";", 1)[0].toLowerCase();
  const size = Number(metadata?.size || 0);
  if (contentType !== "image/jpeg" || !Number.isSafeInteger(size) || size <= 0 || size > MAX_PHOTO_BYTES) {
    throw new HttpsError("failed-precondition", "The profile photo could not be used.");
  }
  const [buffer] = await file.download();
  if (buffer.length !== size || !mimeTypeForImageBuffer(buffer)) {
    throw new HttpsError("failed-precondition", "The profile photo changed during generation.");
  }
  return buffer;
}

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return Number.NaN;
}

async function savePrivatePreviewImage({ bucket, storagePath, buffer }) {
  const file = bucket.file(storagePath);
  await file.save(buffer, {
    resumable: false,
    metadata: { contentType: mimeTypeForImageBuffer(buffer) || "image/png", cacheControl: "private,max-age=86400" }
  });
  return storagePath;
}

async function callOnboardingEditor({ apiKey, model, messages, maxTokens }) {
  const client = new OpenAI({ apiKey, timeout: 15_000, maxRetries: 0 });
  const result = await client.chat.completions.create({
    model, messages, max_completion_tokens: maxTokens,
    reasoning_effort: "minimal", response_format: { type: "json_object" }
  });
  return { text: result.choices?.[0]?.message?.content || "" };
}

async function refineOnboardingStory({ apiKey, rawText, profileName }) {
  if (!apiKey) return { text: refineTranscriptForReading(rawText), model: "deterministic-fallback" };
  return refineTranscriptWithOpenAI({
    apiKey, rawText, glossary: [profileName], callChat: callOnboardingEditor
  });
}

async function loadOwnedReadingCopy({ db, userId, input }) {
  const memories = db.collection("users").doc(userId).collection("memories");
  const ids = [...new Set([input.memoryId, input.memoryId.toUpperCase()])];
  const snapshots = await Promise.all(ids.map(id => memories.doc(id).get()));
  const existing = snapshots.filter(snapshot => snapshot.exists);
  // Ambiguous legacy UUID casing must not silently select a stale duplicate.
  if (existing.length !== 1) return null;
  const memory = existing[0].data() || {};
  if (String(memory.profileID || "").toLowerCase() !== input.profileId ||
      memory.transcriptionStatus !== "completed" ||
      memory.transcriptionRefinementVersion !== TRANSCRIPTION_REFINEMENT_VERSION) return null;
  const edited = typeof memory.transcriptionEdited === "string" ? memory.transcriptionEdited.trim() : "";
  const canonical = edited || (typeof memory.transcription === "string" ? memory.transcription.trim() : "");
  if (!canonical || canonical.replace(/\s+/g, " ") !== input.storyText) return null;
  return {
    text: canonical,
    model: edited ? "narrator-edit" : String(memory.transcriptionRefinementModel || "saved-reading-copy")
  };
}

async function generateOnboardingTitle({ apiKey, storyText, profileName, storytellerRole }) {
  if (!apiKey) return previewTitle(storyText, storytellerRole);
  const ai = createStorybookAI(apiKey, "");
  const context = storytellerRole === "helper"
    ? `The book subject is ${profileName}; a different person is telling their story.`
    : `The narrator is ${profileName}.`;
  const result = await ai.extractTitleAndCharacters(storyText, context, { deadlineAtMs: Date.now() + ONBOARDING_TITLE_WINDOW_MS });
  return result.title;
}

function onboardingPreviewLimit(auth) {
  return auth?.token?.onboardingPreviewTester === true ? 50 : 1;
}

function createOnboardingPreviewHandler({
  db, bucket, geminiApiKey, openaiApiKey, now = () => new Date(),
  generateImage = generateIllustrationBuffer,
  refineStory = refineOnboardingStory,
  generateTitle = generateOnboardingTitle
}) {
  return async request => {
    const handlerStartedAt = Date.now();
    const userId = request.auth?.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");
    await assertAccountNotDeleting(db, userId);
    if (request.data?.warmup === true) return { status: "ready" };
    let input;
    try {
      input = sanitizeOnboardingPreviewRequest(request.data || {}, userId);
    } catch (error) {
      throw new HttpsError("invalid-argument", String(error.message || error));
    }
    const fastIllustration = request.auth?.token?.onboardingPreviewTester === true;
    const imageModel = fastIllustration ? FAST_ONBOARDING_IMAGE_MODEL : ONBOARDING_IMAGE_MODEL;
    const requestHash = onboardingPreviewRequestHash(input);
    const previewLimit = onboardingPreviewLimit(request.auth);
    const userRef = db.collection("users").doc(userId);
    const jobRef = userRef.collection("onboardingPreviewJobs").doc(input.requestId);
    const usageRef = userRef.collection("aiUsage").doc("onboarding_preview_lifetime");
    const deletionRef = db.collection("accountDeletionRequests").doc(userId);
    const timestamp = admin.firestore.Timestamp.fromDate(now());

    const admission = await db.runTransaction(async transaction => {
      const [job, usage, deletion] = await Promise.all([
        transaction.get(jobRef), transaction.get(usageRef), transaction.get(deletionRef)
      ]);
      if (deletion.exists) throw new HttpsError("failed-precondition", "This account is being deleted.");
      if (job.exists) {
        const existing = job.data() || {};
        if (existing.requestHash !== requestHash) {
          throw new HttpsError("already-exists", "A different preview uses this identifier.");
        }
        if (existing.status === "imageReady" && existing.illustrationStoragePath) {
          return { action: "ready", data: existing };
        }
        if (existing.status === "generating") {
          const updatedAtMs = timestampMillis(existing.updatedAt);
          if (Number.isFinite(updatedAtMs) && now().getTime() - updatedAtMs < STALE_GENERATION_MS) {
            return { action: "generating", data: existing };
          }
        }
        const attempts = Number(existing.attempts || 1);
        if (!Number.isSafeInteger(attempts) || attempts >= MAX_GENERATION_ATTEMPTS) {
          throw new HttpsError("resource-exhausted", "This preview could not be completed after several attempts. Your memory is still saved.");
        }
        transaction.update(jobRef, { status: "generating", attempts: attempts + 1, updatedAt: timestamp });
        return { action: "generate" };
      }
      const reserved = Number(usage.data()?.reserved || 0);
      if (!Number.isSafeInteger(reserved) || reserved < 0 || reserved >= previewLimit) {
        throw new HttpsError("resource-exhausted", "The onboarding preview has already been used.");
      }
      transaction.set(usageRef, { reserved: reserved + 1, limit: previewLimit, updatedAt: timestamp }, { merge: true });
      transaction.create(jobRef, {
        requestHash,
        schemaVersion: ONBOARDING_PREVIEW_VERSION,
        profileId: input.profileId,
        memoryId: input.memoryId,
        status: "generating",
        attempts: 1,
        model: imageModel,
        createdAt: timestamp,
        updatedAt: timestamp
      });
      return { action: "generate" };
    });

    if (admission.action === "ready") {
      return {
        status: "imageReady",
        requestId: input.requestId,
        title: admission.data.title,
        readingText: admission.data.readingText || input.storyText,
        refinementModel: admission.data.refinementModel || "unrefined",
        illustrationStoragePath: admission.data.illustrationStoragePath,
        stageTimingsMs: admission.data.stageTimingsMs || null,
        cached: true
      };
    }
    if (admission.action === "generating") {
      return { status: "generating", requestId: input.requestId };
    }

    const startedAt = Date.now();
    const stageTimingsMs = { admission: startedAt - handlerStartedAt };
    const timed = async (stage, operation) => {
      const start = Date.now();
      try { return await operation(); }
      finally { stageTimingsMs[stage] = Date.now() - start; }
    };
    let readingCopyReused = false;
    try {
      const resolvedBucket = typeof bucket === "function" ? bucket() : bucket;
      const resolvedOpenAIKey = typeof openaiApiKey === "function" ? openaiApiKey() : openaiApiKey;
      const titlePromise = timed("title", () => generateTitle({
        apiKey: resolvedOpenAIKey, storyText: input.storyText,
        profileName: input.profileName, storytellerRole: input.storytellerRole
      }).catch(() => previewTitle(input.storyText, input.storytellerRole)));
      const readingPromise = timed("reading", async () => {
        const saved = await timed("ownedReadingLookup", () => loadOwnedReadingCopy({ db, userId, input }))
          .catch(() => null);
        if (saved) {
          readingCopyReused = true;
          return saved;
        }
        return refineStory({
          apiKey: resolvedOpenAIKey, rawText: input.storyText, profileName: input.profileName
        }).catch(() => ({ text: refineTranscriptForReading(input.storyText), model: "deterministic-fallback" }));
      });
      const photo = await timed("photo", () => loadOwnedSubjectPhoto({
        bucket: resolvedBucket,
        userId,
        profileId: input.profileId,
        requestId: input.requestId,
        storagePath: input.subjectPhotoStoragePath
      }));
      const styleReference = fastIllustration ? fastStyleReference : loadStyleReferencePng("normal");
      if (!styleReference) throw new HttpsError("internal", "The book illustration style is unavailable.");
      const prompt = (fastIllustration ? buildFastOnboardingIllustrationPrompt : buildOnboardingIllustrationPrompt)({
        profileName: input.profileName,
        storyText: input.storyText,
        hasHeadshot: Boolean(photo),
        hasStyleReference: true,
        storytellerRole: input.storytellerRole
      });
      const resolvedGeminiApiKey = typeof geminiApiKey === "function"
        ? String(geminiApiKey() || "").trim()
        : String(geminiApiKey || "").trim();
      if (!resolvedGeminiApiKey) throw new HttpsError("internal", "Image generation is unavailable.");
      const image = await timed("image", () => generateImage(
        resolvedGeminiApiKey,
        prompt,
        "4:3",
        photo ? [styleReference, photo] : [styleReference],
        {
          deadlineAtMs: Date.now() + 100_000,
          model: imageModel,
          textFirst: true,
          responseModalities: fastIllustration ? ["TEXT", "IMAGE"] : ["IMAGE"]
        }
      ));
      await assertAccountNotDeleting(db, userId);
      const storagePath = `users/${userId}/onboardingPreviews/${input.requestId}/illustration.png`;
      const storagePromise = timed("storage", () => savePrivatePreviewImage({ bucket: resolvedBucket, storagePath, buffer: image }));
      const [reading, title] = await Promise.all([readingPromise, titlePromise, storagePromise]);
      stageTimingsMs.generation = Date.now() - startedAt;
      stageTimingsMs.overall = Date.now() - handlerStartedAt;
      await jobRef.update({
        status: "imageReady",
        title,
        readingText: reading.text,
        refinementModel: reading.model,
        illustrationStoragePath: storagePath,
        errorCode: admin.firestore.FieldValue.delete(),
        generationDurationMs: Date.now() - startedAt,
        stageTimingsMs,
        readingCopyReused,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(JSON.stringify({
        kind: "onboardingPreview.imageReady",
        userIdHash: safeLogIdentifier(userId),
        requestIdHash: safeLogIdentifier(input.requestId),
        model: imageModel,
        elapsedMs: Date.now() - startedAt,
        overallElapsedMs: Date.now() - handlerStartedAt,
        stageTimingsMs,
        readingCopyReused,
        bytes: image.length,
        hasHeadshot: Boolean(photo)
      }));
      return {
        status: "imageReady",
        requestId: input.requestId,
        title,
        readingText: reading.text,
        refinementModel: reading.model,
        illustrationStoragePath: storagePath,
        imageDataBase64: image.toString("base64"),
        stageTimingsMs,
        readingCopyReused,
        cached: false
      };
    } catch (error) {
      console.error("onboardingPreview generation failed", {
        userIdHash: safeLogIdentifier(userId),
        requestIdHash: safeLogIdentifier(input.requestId),
        ...safeErrorMetadata(error)
      });
      await jobRef.update({
        status: "failed",
        errorCode: String(error?.code || "generation-failed").slice(0, 80),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }).catch(() => {});
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Your preview could not be created. Please try again.");
    }
  };
}

exports.createOnboardingPreview = onCall(
  {
    secrets: [geminiSecret, openaiSecret],
    timeoutSeconds: 120,
    memory: "1GiB",
    concurrency: 4,
    maxInstances: 5,
    region: "us-central1",
    enforceAppCheck: isAppCheckEnforced()
  },
  createOnboardingPreviewHandler({
    db: admin.firestore(),
    bucket: () => admin.storage().bucket(),
    geminiApiKey: secretReader(geminiSecret),
    openaiApiKey: secretReader(openaiSecret)
  })
);

exports._test = {
  ONBOARDING_TITLE_WINDOW_MS,
  secretReader,
  sanitizeOnboardingPreviewRequest,
  onboardingPreviewRequestHash,
  buildOnboardingIllustrationPrompt,
  onboardingAgeDirection,
  refineOnboardingStory,
  loadOwnedReadingCopy,
  callOnboardingEditor,
  onboardingPreviewLimit,
  loadOwnedSubjectPhoto,
  previewTitle,
  generateOnboardingTitle,
  timestampMillis,
  savePrivatePreviewImage,
  createOnboardingPreviewHandler
};
