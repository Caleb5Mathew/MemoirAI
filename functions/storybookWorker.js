/**
 * Firestore-triggered storybook AI generation worker.
 */

const admin = require("firebase-admin");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const pLimit = require("p-limit");
const { sanitizeStorybookFailure } = require("./storybookFailureSanitizer");
const { boundedRetryDelayMs } = require("./retryDeadlinePolicy");
const { createStorybookAI, normalizeArtStyleKey, uploadPngWithDownloadURL } = require("./storybookAI");
const {
  admitLegacyStorybookJob,
  claimStorybookWorkerJob,
  isAdmittedStorybookJob,
  releaseStorybookActiveLease,
  settleStorybookReservation,
  validateSubjectPhotoPathForWorker,
  validateSubjectPhotoForWorker
} = require("./storybookAdmission");
const { assertAccountNotDeleting } = require("./accountStateGuards");

/** Bump when job payload / worker contract changes; older clients get a clear failure instead of obscure promptAssembly errors. */
const STORYBOOK_WORKER_MIN_CLIENT_VERSION = 2;

const openaiSecret = defineSecret("OPENAI_API_KEY");
const geminiSecret = defineSecret("GEMINI_API_KEY");

function firestore() {
  return admin.firestore();
}
function storageBucket() {
  return admin.storage().bucket();
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * When a new storybook job starts, prior failures for the same profile should not
 * keep surfacing in the client banner / resume path. Mark them dismissedFailed (not "active").
 */
async function dismissPriorFailedStorybookJobs(userId, profileId, currentJobId) {
  const pid = String(profileId || "")
    .trim()
    .toLowerCase();
  if (!pid || !userId || !currentJobId) return;
  const qs = await firestore()
    .collection("users")
    .doc(userId)
    .collection("storybookJobs")
    .orderBy("createdAt", "desc")
    .limit(50)
    .get();
  const batch = firestore().batch();
  let writes = 0;
  for (const doc of qs.docs) {
    if (doc.id === currentJobId) continue;
    const d = doc.data() || {};
    const p = String(d.profileId || "")
      .trim()
      .toLowerCase();
    if (p !== pid) continue;
    if (String(d.status || "") !== "failed") continue;
    batch.update(doc.ref, {
      status: "dismissedFailed",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      dismissedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    writes += 1;
    if (writes >= 400) break;
  }
  if (writes > 0) await batch.commit();
}

/**
 * Parses the "Please retry in Xs" suggestion from Gemini 429 bodies.
 * Returns milliseconds to wait, or null if not found.
 */
function parseRetryAfterMs(errorMsg) {
  const match = String(errorMsg || "").match(/retry in (\d+(?:\.\d+)?)s/i);
  if (match) {
    return Math.ceil(parseFloat(match[1]) * 1000) + 1500; // +1.5s buffer
  }
  return null;
}

/**
 * @param {() => Promise} fn
 * @param {{ maxAttempts?: number, isImageCall?: boolean }} opts
 *   isImageCall=true uses more attempts and a longer starting delay to handle
 *   the Gemini image model's 20 RPM quota gracefully.
 */
async function withRetries(fn, {
  maxAttempts = 5,
  isImageCall = false,
  deadlineAtMs = Date.now() + 180_000
} = {}) {
  const attempts = isImageCall ? 6 : maxAttempts;
  let delay = isImageCall ? 15000 : 250;
  let lastErr;
  for (let i = 0; i < attempts; i += 1) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      const status = e?.status || e?.statusCode || e?.response?.status;
      const msg = String(e?.message || e);
      const retryable =
        status === 429 ||
        status === 503 ||
        msg.includes("RESOURCE_EXHAUSTED") ||
        msg.includes("429") ||
        msg.includes("ECONNRESET");
      if (!retryable || i === attempts - 1) throw e;
      // Honour the server's own retry-after suggestion first, then fall back to
      // exponential backoff.  Add ±20% jitter to spread thundering-herd retries.
      const serverMs = parseRetryAfterMs(msg);
      const boundedDelay = boundedRetryDelayMs({
        baseDelayMs: delay,
        serverDelayMs: serverMs,
        jitterFraction: 0.2 * Math.random(),
        nowMs: Date.now(),
        deadlineMs: deadlineAtMs
      });
      if (boundedDelay == null) throw e;
      await sleep(boundedDelay);
      delay = Math.min(delay * 2, isImageCall ? 60000 : 8000);
    }
  }
  throw lastErr;
}

function createWriteQueue() {
  let chain = Promise.resolve();
  return (fn) => {
    const next = chain.then(fn);
    chain = next.catch((e) => {
      console.error("writeQueue task failed", e);
    });
    return next;
  };
}

async function releaseActiveStorybookLease(userId, jobId) {
  try {
    await releaseStorybookActiveLease({ db: firestore(), userId, jobId });
  } catch (error) {
    console.error("storybook active lease release failed", {
      userId,
      jobId,
      code: String(error?.code || "unknown")
    });
  }
}

exports.processStorybookJob = onDocumentCreated(
  {
    document: "users/{userId}/storybookJobs/{jobId}",
    secrets: [openaiSecret, geminiSecret],
    timeoutSeconds: 540,
    memory: "2GiB",
    region: "us-central1",
    retry: true
  },
  async (event) => {
    const { userId, jobId } = event.params;
    const snap = event.data;
    if (!snap) {
      await releaseActiveStorybookLease(userId, jobId);
      return;
    }
    const ref = snap.ref;
    const workerDeadlineAtMs = Date.now() + 500_000;
    let data = snap.data() || {};

    const logJob = (kind, extra) => {
      try {
        console.log(
          JSON.stringify({ kind, jobId, userId, ...(extra || {}) })
        );
      } catch (_) {
        console.log(`[storybookWorker.job] ${kind} ${jobId}`);
      }
    };

    logJob("storybook.jobStart", {
      status: data.status,
      profileId: data.profileId,
      pageCountTarget: data.pageCountTarget,
      artStyleIn: data.artStyle,
      artStyleResolved: normalizeArtStyleKey(data.artStyle),
      hasSubjectPhoto: !!data.subjectPhotoStoragePath,
      otherDetailsLen: String(data.otherDetails || "").length,
      faceDescriptionLen: String(data.faceDescription || "").length,
      customArtStyleLen: String(data.customArtStyleText || "").length,
      styleReferencePreset: data.styleReferencePreset || null,
      clientVersion: data.clientVersion != null ? data.clientVersion : null
    });

    if (!isAdmittedStorybookJob(data)) {
      try {
        const admission = await admitLegacyStorybookJob({
          db: firestore(),
          jobRef: ref,
          userId,
          jobId,
          serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
          timestampFromDate: (date) => admin.firestore.Timestamp.fromDate(date),
          minimumClientVersion: STORYBOOK_WORKER_MIN_CLIENT_VERSION
        });
        if (admission.status === "missing") return;
        const admittedSnapshot = await ref.get();
        data = admittedSnapshot.data() || {};
        logJob("storybook.legacyJobAdmitted", { status: admission.status });
      } catch (error) {
        if (!error?.permanent) throw error;
        const safeFailure = sanitizeStorybookFailure(error);
        await ref.update({
          status: "failed",
          error: safeFailure.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        logJob("storybook.legacyAdmissionRejected", { code: safeFailure.code });
        return;
      }
    }

    let workerClaim;
    try {
      workerClaim = await claimStorybookWorkerJob({
        db: firestore(),
        jobRef: ref,
        userId,
        jobId,
        serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
        timestampFromDate: (date) => admin.firestore.Timestamp.fromDate(date)
      });
    } catch (error) {
      logJob("storybook.workerClaimFailed", { code: String(error?.code || "unknown") });
      throw error;
    }

    if (workerClaim.action === "retry_later") {
      const retryError = new Error("storybook worker lease is still fresh");
      retryError.code = "retry-later";
      throw retryError;
    }

    if (workerClaim.action !== "claimed") {
      logJob("storybook.skipWorkerClaim", {
        action: workerClaim.action,
        status: workerClaim.status || null
      });
      if (
        workerClaim.action === "missing" ||
        workerClaim.action === "account_deleting" ||
        workerClaim.action === "rejected" ||
        workerClaim.action === "attempts_exhausted" ||
        ["aiComplete", "complete", "failed", "dismissedFailed"].includes(workerClaim.status)
      ) {
        await releaseActiveStorybookLease(userId, jobId);
      }
      return;
    }
    data = workerClaim.data;

    let releaseLeaseWhenDone = true;
    try {
      await assertAccountNotDeleting(firestore(), userId);
      const openaiApiKey = String(openaiSecret.value() || "").trim();
      const geminiApiKey = String(geminiSecret.value() || "").trim();
      if (!openaiApiKey || !geminiApiKey) {
        logJob("storybook.missingSecrets", { hasOpenAI: !!openaiApiKey, hasGemini: !!geminiApiKey });
        await ref.update({
          status: "failed",
          error: "Missing OPENAI_API_KEY or GEMINI_API_KEY secrets",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        return;
      }

      const ai = createStorybookAI(openaiApiKey, geminiApiKey);
      const enqueueWrite = createWriteQueue();

      const clientVersion = parseInt(String(data.clientVersion ?? "0"), 10) || 0;
      if (clientVersion < STORYBOOK_WORKER_MIN_CLIENT_VERSION) {
        logJob("storybook.clientVersionRejected", {
          clientVersion,
          requiredMin: STORYBOOK_WORKER_MIN_CLIENT_VERSION
        });
        await ref.update({
          status: "failed",
          error:
            "This storybook job was created with an older app version than this server supports. Please update MemoirAI from the App Store (or reinstall the latest build) and start a new generation.",
          "progress.currentStatus": "Please update the app and retry.",
          lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        return;
      }

      try {
        await dismissPriorFailedStorybookJobs(userId, String(data.profileId || ""), jobId);
      } catch (e) {
        console.warn("[storybookWorker] dismissPriorFailedStorybookJobs", e);
      }

    try {
      const profileId = String(data.profileId || "");
      const pageCountTarget = Math.max(1, parseInt(String(data.pageCountTarget || "1"), 10) || 1);
      const artStyle = normalizeArtStyleKey(data.artStyle);
      const stylePreset = String(data.styleReferencePreset || "normal");

      const job = {
        profileName: data.profileName || "",
        profileEthnicity: data.profileEthnicity || "",
        gender: data.gender || "",
        otherDetails: data.otherDetails || "",
        faceDescription: data.faceDescription || "",
        customArtStyleText: data.customArtStyleText || ""
      };
      const pinnedRaw = data.pinnedMemoryIds;
      const pinnedIds = Array.isArray(pinnedRaw)
        ? pinnedRaw.map((x) => String(x || "").trim()).filter(Boolean)
        : [];

      const profileIdVariants = Array.from(new Set([
        profileId,
        profileId.toLowerCase(),
        profileId.toUpperCase()
      ]));
      const memSnap = await firestore()
        .collection("users")
        .doc(userId)
        .collection("memories")
        .where("profileID", "in", profileIdVariants)
        .limit(200)
        .get();
      const memoriesCollection = firestore().collection("users").doc(userId).collection("memories");
      const pinnedSnapshots = pinnedIds.length > 0
        ? await firestore().getAll(...pinnedIds.map((id) => memoriesCollection.doc(id)))
        : [];
      const candidateDocuments = new Map(memSnap.docs.map((document) => [document.id, document]));
      for (const document of pinnedSnapshots) {
        if (document.exists) candidateDocuments.set(document.id, document);
      }
      const profileIdNorm = String(profileId || "").toLowerCase();
      const memories = Array.from(candidateDocuments.values())
        .map((d) => {
          const x = d.data();
          return {
            id: d.id,
            profileID: String(x.profileID || ""),
            transcription: String(x.transcription || "").slice(0, 50_000),
            prompt: String(x.prompt || "").slice(0, 2_000),
            characterDetails: x.characterDetails != null ? String(x.characterDetails).slice(0, 20_000) : "",
            chapter: x.chapter != null ? String(x.chapter).slice(0, 500) : ""
          };
        })
        .filter((m) => m.profileID.toLowerCase() === profileIdNorm);

      logJob("storybook.fetchedMemories", {
        candidateCount: candidateDocuments.size,
        forProfile: memories.length,
        nonEmptyTranscriptions: memories.filter((m) => m.transcription.trim().length > 0).length
      });

      for (const m of memories) {
        logJob("storybook.memorySnapshot", {
          memoryId: m.id,
          transcriptionLen: m.transcription.length,
          characterDetailsLen: m.characterDetails.length
        });
      }

      if (memories.length === 0) {
        await ref.update({
          status: "failed",
          error: "No synced memories match this profile yet. Save a memory for this person, then try again.",
          "progress.currentStatus": "No cloud memories for this profile.",
          lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        return;
      }

      const memById = new Map(memories.map((m) => [String(m.id || "").toLowerCase(), m]));

      let ranked;
      if (pinnedIds.length > 0) {
        const pinnedOrdered = [];
        const seenPin = new Set();
        for (const pid of pinnedIds) {
          const key = pid.toLowerCase();
          if (seenPin.has(key)) continue;
          seenPin.add(key);
          const m = memById.get(key);
          if (m) pinnedOrdered.push(m);
        }
        const pinSet = new Set(pinnedOrdered.map((m) => String(m.id || "").toLowerCase()));
        logJob("storybook.rankingStart", {
          input: memories.length,
          target: pageCountTarget,
          mode: "pinnedPlusRank",
          pinnedCount: pinnedOrdered.length,
          pinnedIds: pinnedOrdered.map((m) => m.id)
        });
        if (pinnedOrdered.length > pageCountTarget) {
          ranked = await ai.rankMemoriesWithLLM(pinnedOrdered, pageCountTarget);
        } else {
          const needed = pageCountTarget - pinnedOrdered.length;
          const rest = memories.filter((m) => !pinSet.has(String(m.id || "").toLowerCase()));
          const rankedRest = needed > 0 ? await ai.rankMemoriesWithLLM(rest, needed) : [];
          ranked = pinnedOrdered.concat(rankedRest);
        }
      } else {
        logJob("storybook.rankingStart", { input: memories.length, target: pageCountTarget, mode: "rankAll" });
        ranked = await ai.rankMemoriesWithLLM(memories, pageCountTarget);
      }
      logJob("storybook.rankingDone", {
        ranked: ranked.length
      });
      const ageLimit = pLimit(12);
      const ages = await Promise.all(
        ranked.map((m) => ageLimit(() =>
          ai.extractAge(String(m.transcription || ""), String(m.characterDetails || ""))
        ))
      );
      const ordered = ranked
        .map((m, i) => ({ m, age: ages[i] ?? 999 }))
        .sort((a, b) => a.age - b.age)
        .map((x) => x.m);

      const orderedMemoryIds = ordered.map((m) => m.id);
      logJob("storybook.orderedMemories", {
        count: orderedMemoryIds.length
      });

      const castCanon = ai.buildCastCanon(ordered, job);
      logJob("storybook.castCanon", { count: (castCanon.rows || []).length });

      await ref.update({
        status: "running",
        orderedMemoryIds,
        runningStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        progress: {
          totalMemories: ordered.length,
          completedMemoryCount: 0,
          currentStatus: "Generating illustrations…"
        },
        skippedMemoryIds: [],
        lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      let headshotBuf = null;
      const photoPath = data.subjectPhotoStoragePath;
      if (photoPath && typeof photoPath === "string") {
        try {
          validateSubjectPhotoPathForWorker({ userId, profileId, storagePath: photoPath });
          const photoFile = storageBucket().file(photoPath);
          const [metadata] = await photoFile.getMetadata();
          const validatedPhoto = validateSubjectPhotoForWorker({
            userId,
            profileId,
            storagePath: photoPath,
            metadata
          });
          const [buf] = await storageBucket()
            .file(photoPath, { generation: validatedPhoto.generation })
            .download();
          if (buf.length !== validatedPhoto.size) {
            throw new Error("subject photo changed after metadata validation");
          }
          headshotBuf = buf;
          logJob("storybook.headshotDownloaded", { bytes: buf.length });
        } catch (e) {
          logJob("storybook.headshotDownloadFailed", {
            code: String(e?.code || "unknown")
          });
        }
      } else {
        logJob("storybook.noHeadshotConfigured");
      }
      job._hasHeadshot = !!headshotBuf;

      const styleRefBuf = artStyle === "kidsBook" ? ai.loadStyleReferencePng(stylePreset) : null;
      logJob("storybook.styleReference", {
        artStyle,
        stylePreset,
        styleRefAttached: !!styleRefBuf,
        styleRefBytes: styleRefBuf ? styleRefBuf.length : 0
      });
      const maxParallel = Math.max(
        1,
        Math.min(parseInt(process.env.STORYBOOK_MAX_PARALLEL || "12", 10) || 12, 24)
      );
      const limit = pLimit(maxParallel);
      // Gemini image model hard quota: 20 RPM.  Each image takes ~8-15s, so
      // at most 3 concurrent calls keeps us well under the limit regardless of
      // how high maxParallel is set.
      const imageParallel = Math.max(
        1,
        Math.min(parseInt(process.env.STORYBOOK_IMAGE_PARALLEL || "3", 10) || 3, 5)
      );
      const imageLimit = pLimit(imageParallel);

      const phaseLog = (mid, stage, extra) => {
        // Structured one-line JSON logs make Cloud Logging filtering trivial:
        // resource.labels.service_name="processstorybookjob" jsonPayload.stage="image"
        try {
          console.log(
            JSON.stringify({
              kind: "storybook.phase",
              jobId,
              userId,
              memoryId: mid,
              stage,
              ...(extra || {})
            })
          );
        } catch (_) {
          console.log(`[storybookWorker.phase] ${mid} ${stage}`);
        }
      };

      const processOne = async (entry) => {
        const jr = await ref.get();
        const jd = jr.data() || {};
        const existing = jd.memoryResults && jd.memoryResults[entry.id];
        if (existing && existing.illustrationStoragePath) {
          phaseLog(entry.id, "resume.skip", { reason: "already-have-illustration" });
          return { id: entry.id, resumed: true };
        }

        const raw = String(entry.transcription || "").trim();
        if (!raw) {
          phaseLog(entry.id, "skip.empty");
          await enqueueWrite(() =>
            ref.update({
              skippedMemoryIds: admin.firestore.FieldValue.arrayUnion(entry.id),
              [`memoryFailures.${entry.id}`]: {
                stage: "validate",
                message: "Memory has no transcription text.",
                at: admin.firestore.Timestamp.now()
              },
              "progress.completedMemoryCount": admin.firestore.FieldValue.increment(1),
              lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            })
          );
          return { id: entry.id, empty: true };
        }

        // Track the stage we're currently in so the catch handler can
        // pinpoint which step blew up (otherwise every failure looks the same).
        let stage = "init";
        try {
          stage = "scene";
          phaseLog(entry.id, stage);
          const enrichedDetailsStr = ai.enrichEntryCharacterDetailsFromCanon(entry, castCanon, job);
          const entryForPrompt = { ...entry, characterDetails: enrichedDetailsStr };
          const characterContext = ai.buildCharacterContextFromDetails(enrichedDetailsStr, job, raw);
          logJob("storybook.enrichment", {
            memoryId: entry.id,
            transcriptLen: raw.length,
            characterDetailsInLen: String(entry.characterDetails || "").length,
            characterDetailsEnrichedLen: enrichedDetailsStr.length,
            characterContextLen: String(characterContext || "").length
          });
          let sceneDescription = await withRetries(
            () => ai.extractVisualScene(raw, characterContext),
            { deadlineAtMs: workerDeadlineAtMs }
          );
          const COLLECTIVE_RE =
            /\b(?:the group of (?:friends|kids|boys|girls)|the (?:kids|team|boys|girls|family))\b/i;
          if (COLLECTIVE_RE.test(sceneDescription)) {
            logJob("storybook.sceneCollectiveDetected", { memoryId: entry.id });
            sceneDescription = await withRetries(
              () => ai.extractVisualScene(
                raw,
                `${characterContext}\n\nIMPORTANT: Name every listed person by their exact display names in your paragraph. Do NOT use collective phrases like "the group of friends" or "the kids".`
              ),
              { deadlineAtMs: workerDeadlineAtMs }
            );
          }
          logJob("storybook.scene", { memoryId: entry.id, sceneLen: sceneDescription.length });

          stage = "title";
          phaseLog(entry.id, stage);
          const extracted = await withRetries(
            () => ai.extractTitleAndCharacters(raw, characterContext),
            { deadlineAtMs: workerDeadlineAtMs }
          );
          logJob("storybook.title", {
            memoryId: entry.id,
            titleLen: String(extracted.title || "").length,
            featuringCount: String(extracted.featuring || "").split(",").filter(Boolean).length
          });

          stage = "narrator";
          const narrator = ai.inferNarratorPresence(raw, entry.chapter, job.profileName);
          const headshotDecision = ai.shouldAttachHeadshot({
            narratorPresence: narrator.presence,
            headshotBuf,
            characterDetailsStr: enrichedDetailsStr,
            transcript: raw,
            profileName: job.profileName
          });
          const attachHeadshot = headshotDecision.attach;
          const matchesProfileFirstToken = ai.nameMatchesProfileFirstToken(enrichedDetailsStr, raw, job.profileName);
          const includeNarratorInRoster =
            narrator.presence !== "likelyAbsent" || matchesProfileFirstToken;
          logJob("storybook.narrator", {
            memoryId: entry.id,
            narratorPresence: narrator.presence,
            narratorConfidenceScore: narrator.confidenceScore != null ? narrator.confidenceScore : null,
            narratorFirstPersonDetected: !!narrator.firstPersonDetected,
            attachHeadshot,
            headshotReason: headshotDecision.reason,
            hasHeadshotBuf: !!headshotBuf,
            matchesProfileFirstToken,
            includeNarratorInRoster
          });

          stage = "promptAssembly";
          const characterList = ai.buildCharacterList(entryForPrompt, job, sceneDescription, includeNarratorInRoster);
          const filteredCanonRows = ai.filterCanonRowsForEntry(castCanon, entry);
          const canonLines = filteredCanonRows.map((r) => ai.canonRowToPromptLine(r, { forImagePrompt: true, job }));
          const referenceImageOrder = [];
          if (styleRefBuf) referenceImageOrder.push("style");
          if (attachHeadshot && headshotBuf) referenceImageOrder.push("headshot");

          const assembled = ai.assembleFinalPrompt(
            raw,
            characterList,
            narrator.presence,
            sceneDescription,
            artStyle,
            job.customArtStyleText,
            !!(attachHeadshot && headshotBuf),
            job,
            stylePreset,
            { canonLines, referenceImageOrder, characterDetailsForAge: enrichedDetailsStr }
          );

          logJob("storybook.assembledPreview", {
            memoryId: entry.id,
            artStyleIn: data.artStyle,
            artStyleResolved: artStyle,
            hasStyleRef: !!styleRefBuf,
            attachHeadshot,
            refs: referenceImageOrder,
            canonLineCount: canonLines.length,
            characterListLen: String(characterList || "").length,
            promptLen: assembled.length
          });

          const refs = [];
          if (styleRefBuf) refs.push(styleRefBuf);
          if (attachHeadshot && headshotBuf) refs.push(headshotBuf);

          stage = "image";
          phaseLog(entry.id, stage, {
            promptLen: assembled.length,
            includesNarrator: includeNarratorInRoster,
            attachHeadshot,
            hasHeadshot: !!headshotBuf,
            hasStyleRef: !!styleRefBuf,
            artStyle,
            headshotReason: headshotDecision.reason
          });
          const geminiSize = artStyle === "kidsBook" ? "4:3" : "1792x1024";
          const imageStartMs = Date.now();
          await assertAccountNotDeleting(firestore(), userId);
          // imageLimit caps concurrent Gemini image calls; isImageCall enables
          // the longer backoff + more retries tuned for 429 RESOURCE_EXHAUSTED.
          const imageBuf = await imageLimit(() =>
            withRetries(
              () =>
                ai.generateIllustrationBufferGuarded(geminiApiKey, assembled, geminiSize, refs, (event, details) =>
                  logJob(event, { memoryId: entry.id, ...details })
                ),
              { isImageCall: true, deadlineAtMs: workerDeadlineAtMs }
            )
          );
          if (!imageBuf || !imageBuf.length) {
            // Defensive: generateIllustrationBuffer should now always throw on
            // missing image, but guard in case a future change regresses.
            const err = new Error("Gemini returned no image bytes (empty buffer).");
            err.noImageBytes = true;
            throw err;
          }

          const imageElapsedMs = Date.now() - imageStartMs;
          logJob("storybook.imageDone", {
            memoryId: entry.id,
            elapsedMs: imageElapsedMs,
            bytes: imageBuf.length,
            geminiSize,
            refsCount: refs.length
          });

          stage = "upload";
          phaseLog(entry.id, stage);
          await assertAccountNotDeleting(firestore(), userId);
          const storagePath = `users/${userId}/bookVersions/${jobId}/illustration_${entry.id}.png`;
          const { url } = await uploadPngWithDownloadURL(storagePath, imageBuf);
          try {
            await assertAccountNotDeleting(firestore(), userId);
          } catch (error) {
            try {
              await storageBucket().file(storagePath).delete();
            } catch (deleteError) {
              if (Number(deleteError?.code || 0) !== 404) throw deleteError;
            }
            throw error;
          }

          stage = "persist";
          const questionDriven = ai.isQuestionDrivenMemory(entry);
          const memPrompt = String(entry.prompt || "").trim();
          const displayTitle = questionDriven ? (memPrompt || extracted.title) : extracted.title;
          const displaySubtitle = questionDriven ? extracted.title : null;
          const llmBarTitle = String(extracted.title || "").trim();
          const illustrationBarTitle = llmBarTitle || displayTitle;

          const memResult = {
            displayTitle: displayTitle || "Memory",
            displaySubtitle: displaySubtitle || null,
            sceneDescription,
            illustrationStoragePath: storagePath,
            illustrationURL: url,
            narratorPresence: narrator.presence,
            narratorReason: narrator.reason || null,
            narratorConfidenceScore: narrator.confidenceScore != null ? narrator.confidenceScore : null,
            extractedTitle: extracted.title,
            illustrationBarTitle,
            completedAt: admin.firestore.Timestamp.now(),
            headshotAttached: !!(attachHeadshot && headshotBuf),
            headshotPolicyReason: headshotDecision.reason,
            canonAmbiguousFor: filteredCanonRows.filter((r) => r.canonAmbiguous).map((r) => r.displayLabel || r.nameToken),
            refsUsed: referenceImageOrder.slice(),
            assembledPromptChars: assembled.length
          };

          await enqueueWrite(() =>
            ref.update({
              [`memoryResults.${entry.id}`]: memResult,
              [`memoryFailures.${entry.id}`]: admin.firestore.FieldValue.delete(),
              "progress.completedMemoryCount": admin.firestore.FieldValue.increment(1),
              "progress.currentStatus": `Generated ${entry.id.slice(0, 8)}…`,
              lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            })
          );
          phaseLog(entry.id, "ok");
          return { id: entry.id, ok: true };
        } catch (e) {
          if (e?.accountDeletionRequested) throw e;
          const failure = sanitizeStorybookFailure(
            e,
            stage,
            admin.firestore.Timestamp.now()
          );
          console.error(
            JSON.stringify({
              kind: "storybook.memoryFailed",
              jobId,
              memoryId: entry.id,
              stage: failure.stage,
              httpStatus: failure.httpStatus || null,
              errorName: failure.errorName || null
            })
          );
          await enqueueWrite(() =>
            ref.update({
              skippedMemoryIds: admin.firestore.FieldValue.arrayUnion(entry.id),
              [`memoryFailures.${entry.id}`]: failure,
              "progress.completedMemoryCount": admin.firestore.FieldValue.increment(1),
              lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            })
          );
          return { id: entry.id, err: failure.message, stage };
        }
      };

      await Promise.all(ordered.map((entry) => limit(() => processOne(entry))));

      // Re-read job doc to count how many memories actually produced an
      // illustration.  If none did, mark the job as failed so the client
      // doesn't get stuck in a finalize loop with empty pageItems.
      const finalSnap = await ref.get();
      const finalData = finalSnap.data() || {};
      const finalResults = finalData.memoryResults || {};
      const finalFailures = finalData.memoryFailures || {};
      const successCount = Object.values(finalResults).filter(
        (r) => r && r.illustrationStoragePath
      ).length;

      if (successCount === 0) {
        // Build a real summary from the captured per-memory diagnostics
        // instead of guessing.  Group failures by stage + message so the
        // user-visible string is something we actually verified happened.
        const failureList = Object.values(finalFailures);
        const groups = {};
        for (const f of failureList) {
          const key = `${f.stage || "unknown"}::${f.message || ""}`;
          groups[key] = (groups[key] || 0) + 1;
        }
        const topGroups = Object.entries(groups)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 3)
          .map(([key, count]) => {
            const [stage, msg] = key.split("::");
            return `${count}× [${stage}] ${msg}`;
          });
        const summary =
          failureList.length === 0
            ? "Image generation finished without any successful or failed memories. This is unusual — please try again."
            : `All ${failureList.length} memor${failureList.length === 1 ? "y" : "ies"} failed during cloud generation. Top reasons: ${topGroups.join(" | ")}`;

        console.error(
          JSON.stringify({
            kind: "storybook.allFailed",
            jobId,
            failureCount: failureList.length,
            groups
          })
        );
        await ref.update({
          status: "failed",
          error: summary,
          "progress.currentStatus": "Image generation failed for every memory.",
          lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        return;
      }

      const excerpt = ordered
        .map((m) => String(m.transcription || "").split(/\s+/).slice(0, 80).join(" "))
        .join("\n\n")
        .slice(0, 2500);
      const bookTitle = String(data.bookDisplayTitle || data.profileName || "Memoir").trim();
      const pitchPrompt = `You are a book jacket copywriter. Write a short warm back-cover blurb (3-5 sentences) for a printed memoir titled "${bookTitle}" using this excerpt:\n\n${excerpt}`;
      let pitch = "";
      try {
        pitch = (await ai.generateBackCoverPitch(pitchPrompt)) || "";
      } catch (pitchErr) {
        console.error(
          JSON.stringify({
            kind: "storybook.backCoverPitchFailed",
            jobId,
            errorName: String(pitchErr?.name || "Error").slice(0, 80)
          })
        );
      }
      if (!String(pitch || "").trim()) {
        const themeHints = ordered
          .map((m) => String(m.prompt || "").trim())
          .filter(Boolean)
          .slice(0, 5)
          .join("; ");
        pitch = themeHints
          ? `A warm collection of life moments — including ${themeHints}. Perfect for family to read together.`
          : "A warm collection of life moments captured as a keepsake memoir — perfect for family to read together.";
      }

      const profileTok = (() => {
        const t = String(job.profileName || "")
          .trim()
          .split(/\s+/)[0];
        return t ? t.toLowerCase() : "";
      })();
      const protagonistRow =
        profileTok && castCanon.rows
          ? castCanon.rows.find((r) => r.nameToken === profileTok)
          : null;
      const protagonistCanonCard = protagonistRow ? ai.canonRowToPromptLine(protagonistRow) : "";

      logJob("storybook.aiComplete", {
        successCount,
        failureCount: Object.keys(finalFailures).length,
        pitchLen: (pitch || "").length
      });

      await ref.update({
        status: "aiComplete",
        backCoverPitch: pitch,
        protagonistCanonCard,
        "progress.currentStatus": "Illustrations ready. Finishing your book…",
        lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (e) {
      console.error(
        JSON.stringify({
          kind: "storybook.fatal",
          jobId,
          errorName: String(e?.name || "Error").slice(0, 80)
        })
      );
      releaseLeaseWhenDone = false;
      await ref.update({
        "progress.currentStatus": "Cloud generation was interrupted. Retrying…",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }).catch(() => {});
      throw e;
    }
    } finally {
      if (releaseLeaseWhenDone) {
        await releaseActiveStorybookLease(userId, jobId);
      }
    }
  }
);

exports.continueStorybookJob = onDocumentUpdated(
  {
    document: "users/{userId}/storybookJobs/{jobId}",
    secrets: [openaiSecret, geminiSecret],
    timeoutSeconds: 60,
    memory: "512MiB",
    region: "us-central1"
  },
  async (event) => {
    const after = event.data.after.data();
    if (!after || after.status !== "running_continue") return;
    console.log("[storybookWorker] continueStorybookJob: running_continue (v1 no-op)", event.params.jobId);
  }
);

// Kept separate from the generation worker so it can be deployed alongside
// admission while the previous production worker drains older client jobs.
exports.settleStorybookJobReservation = onDocumentUpdated(
  {
    document: "users/{userId}/storybookJobs/{jobId}",
    timeoutSeconds: 60,
    memory: "256MiB",
    region: "us-central1",
    retry: true
  },
  async (event) => {
    const beforeStatus = event.data?.before?.data()?.status;
    const afterStatus = event.data?.after?.data()?.status;
    if (beforeStatus === afterStatus) return;
    if (!["aiComplete", "complete", "failed", "dismissedFailed"].includes(afterStatus)) return;
    const snapshot = event.data?.after;
    if (!snapshot) return;
    await settleStorybookReservation({
      db: firestore(),
      jobRef: snapshot.ref,
      userId: event.params.userId,
      serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp()
    });
    await releaseStorybookActiveLease({
      db: firestore(),
      userId: event.params.userId,
      jobId: event.params.jobId
    });
  }
);
