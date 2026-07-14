/**
 * Firestore-triggered storybook AI generation worker.
 */

const admin = require("firebase-admin");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const pLimit = require("p-limit");
const { createStorybookAI, normalizeArtStyleKey, uploadPngWithDownloadURL } = require("./storybookAI");

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
async function withRetries(fn, { maxAttempts = 5, isImageCall = false } = {}) {
  const attempts = isImageCall ? 10 : maxAttempts;
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
      const base = serverMs != null ? Math.max(serverMs, delay) : delay;
      const jitter = Math.floor(base * 0.2 * Math.random());
      await sleep(base + jitter);
      delay = Math.min(delay * 2, isImageCall ? 60000 : 8000);
    }
  }
  throw lastErr;
}

function createWriteQueue() {
  let chain = Promise.resolve();
  return (fn) => {
    const next = chain.then(fn).catch((e) => {
      console.error("writeQueue task failed", e);
    });
    chain = next;
    return next;
  };
}

exports.processStorybookJob = onDocumentCreated(
  {
    document: "users/{userId}/storybookJobs/{jobId}",
    secrets: [openaiSecret, geminiSecret],
    timeoutSeconds: 540,
    memory: "2GiB",
    region: "us-central1"
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const { userId, jobId } = event.params;
    const ref = snap.ref;
    const data = snap.data() || {};

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
      subjectPhotoPath: data.subjectPhotoStoragePath || null,
      profileName: data.profileName || null,
      profileEthnicity: data.profileEthnicity || null,
      gender: data.gender || null,
      otherDetailsLen: String(data.otherDetails || "").length,
      faceDescriptionLen: String(data.faceDescription || "").length,
      customArtStyleLen: String(data.customArtStyleText || "").length,
      styleReferencePreset: data.styleReferencePreset || null,
      faceDescriptionHead: String(data.faceDescription || "").slice(0, 240),
      otherDetailsHead: String(data.otherDetails || "").slice(0, 240),
      customArtStyleHead: String(data.customArtStyleText || "").slice(0, 240),
      clientVersion: data.clientVersion != null ? data.clientVersion : null
    });

    if (["running", "aiComplete", "complete", "failed"].includes(data.status)) {
      logJob("storybook.skipAlreadyStarted", { status: data.status });
      return;
    }

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
      await ref.update({
        status: "ranking",
        lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

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

      const memSnap = await firestore().collection("users").doc(userId).collection("memories").get();
      const profileIdNorm = String(profileId || "").toLowerCase();
      const memories = memSnap.docs
        .map((d) => {
          const x = d.data();
          return {
            id: d.id,
            profileID: String(x.profileID || ""),
            transcription: String(x.transcription || ""),
            prompt: String(x.prompt || ""),
            characterDetails: x.characterDetails != null ? String(x.characterDetails) : "",
            chapter: x.chapter != null ? String(x.chapter) : ""
          };
        })
        .filter((m) => m.profileID.toLowerCase() === profileIdNorm);

      // Surface the per-doc profileID values (truncated) so we can spot
      // case/format mismatches between the storybookJob's profileId and the
      // memories' profileID field.
      const sampleProfileIds = memSnap.docs
        .map((d) => String(d.data().profileID || ""))
        .filter(Boolean)
        .slice(0, 10);
      logJob("storybook.fetchedMemories", {
        totalInUser: memSnap.docs.length,
        forProfile: memories.length,
        nonEmptyTranscriptions: memories.filter((m) => m.transcription.trim().length > 0).length,
        wantedProfileId: profileIdNorm,
        sampleProfileIdsSeen: sampleProfileIds
      });

      // Per-memory snapshot so we can reconstruct exactly what the worker saw.
      // Cloud Logging supports ~256KB per entry; transcripts of 0–10k chars fit.
      // characterDetails JSON is dumped wholesale so we can match traits in postmortems.
      for (const m of memories) {
        logJob("storybook.memorySnapshot", {
          memoryId: m.id,
          profileID: m.profileID,
          chapter: m.chapter || null,
          prompt: m.prompt || null,
          transcriptionLen: m.transcription.length,
          characterDetailsLen: m.characterDetails.length,
          transcription: m.transcription,
          characterDetails: m.characterDetails
        });
      }

      if (memories.length === 0) {
        // Distinguish "zero memories synced for this user at all" from
        // "memories exist but none match the profile we're generating for".
        if (memSnap.docs.length === 0) {
          await ref.update({
            status: "failed",
            error:
              "No memories have synced to the cloud yet. Open a memory on this device and tap save once to trigger sync, then try again.",
            "progress.currentStatus": "No cloud memories.",
            lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          });
          return;
        }
        // Memories exist but none have matching profileID — almost always a
        // case/format mismatch or memories assigned to a different profile.
        const distinct = Array.from(new Set(sampleProfileIds));
        await ref.update({
          status: "failed",
          error: `Found ${memSnap.docs.length} memories on the cloud, but none match this profile (${profileIdNorm}). Memories are tagged with profile IDs: ${distinct.join(", ") || "(none set)"}.`,
          "progress.currentStatus": "Profile ID mismatch.",
          lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        return;
      }

      const pinnedRaw = data.pinnedMemoryIds;
      const pinnedIds = Array.isArray(pinnedRaw)
        ? pinnedRaw.map((x) => String(x || "").trim()).filter(Boolean)
        : [];
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
        ranked: ranked.length,
        rankedIds: ranked.map((m) => m.id)
      });
      const ages = await Promise.all(
        ranked.map((m) => ai.extractAge(String(m.transcription || ""), String(m.characterDetails || "")))
      );
      const ordered = ranked
        .map((m, i) => ({ m, age: ages[i] ?? 999 }))
        .sort((a, b) => a.age - b.age)
        .map((x) => x.m);

      const orderedMemoryIds = ordered.map((m) => m.id);
      logJob("storybook.orderedMemories", {
        orderedIds: orderedMemoryIds,
        ages: ranked.map((m, i) => ({ id: m.id, age: ages[i] ?? null }))
      });

      const castCanon = ai.buildCastCanon(ordered, job);
      // Strip private debug fields (`_sources`, `ambiguous` markers) but keep the row shape so we can
      // verify cross-memory continuity decisions in production.
      const sanitizedCanon = (castCanon.rows || []).map((r) => ({
        nameToken: r.nameToken,
        displayLabel: r.displayLabel || null,
        canonAmbiguous: !!r.canonAmbiguous,
        ethnicity: r.ethnicity || null,
        gender: r.gender || null,
        age: r.age || null,
        hairAndFeatures: r.hairAndFeatures || null,
        clothing: r.clothing || null,
        relationshipToNarrator: r.relationshipToNarrator || null,
        memoryIds: r.memoryIds || null
      }));
      logJob("storybook.castCanon", { count: sanitizedCanon.length, rows: sanitizedCanon });

      await ref.update({
        status: "running",
        orderedMemoryIds,
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
          const [buf] = await storageBucket().file(photoPath).download();
          headshotBuf = buf;
          logJob("storybook.headshotDownloaded", { path: photoPath, bytes: buf.length });
        } catch (e) {
          logJob("storybook.headshotDownloadFailed", {
            path: photoPath,
            message: String(e?.message || e)
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
            characterDetailsEnriched: enrichedDetailsStr,
            characterContextLen: String(characterContext || "").length,
            characterContext: String(characterContext || "")
          });
          let sceneDescription = await withRetries(() => ai.extractVisualScene(raw, characterContext));
          const COLLECTIVE_RE =
            /\b(?:the group of (?:friends|kids|boys|girls)|the (?:kids|team|boys|girls|family))\b/i;
          if (COLLECTIVE_RE.test(sceneDescription)) {
            logJob("storybook.sceneCollectiveDetected", { memoryId: entry.id, sceneDescription });
            sceneDescription = await withRetries(() =>
              ai.extractVisualScene(
                raw,
                `${characterContext}\n\nIMPORTANT: Name every listed person by their exact display names in your paragraph. Do NOT use collective phrases like "the group of friends" or "the kids".`
              )
            );
          }
          logJob("storybook.scene", { memoryId: entry.id, sceneLen: sceneDescription.length, sceneDescription });

          stage = "title";
          phaseLog(entry.id, stage);
          const extracted = await withRetries(() => ai.extractTitleAndCharacters(raw, characterContext));
          logJob("storybook.title", {
            memoryId: entry.id,
            extractedTitle: extracted.title,
            featuring: extracted.featuring || ""
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
            narratorReason: narrator.reason || null,
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
            characterList: String(characterList || ""),
            canonLines,
            styleParagraph: ai.artStyleMemoryIllustrationStyleDescription(artStyle, job.customArtStyleText),
            promptLen: assembled.length
          });
          // Full assembled prompt — chunked across multiple log lines because Cloud Logging
          // entries are capped (~256KB) and the Firebase console truncates very long values.
          // Disable by setting `STORYBOOK_LOG_FULL_PROMPT=false` in the function env.
          if (process.env.STORYBOOK_LOG_FULL_PROMPT !== "false") {
            const PROMPT_CHUNK = 3500;
            const total = assembled.length;
            const chunkCount = Math.ceil(total / PROMPT_CHUNK);
            for (let i = 0; i < chunkCount; i += 1) {
              const start = i * PROMPT_CHUNK;
              const end = Math.min(start + PROMPT_CHUNK, total);
              logJob("storybook.assembledFull", {
                memoryId: entry.id,
                part: i + 1,
                totalParts: chunkCount,
                offset: start,
                total,
                chunk: assembled.slice(start, end)
              });
            }
          }

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
          // imageLimit caps concurrent Gemini image calls; isImageCall enables
          // the longer backoff + more retries tuned for 429 RESOURCE_EXHAUSTED.
          const imageBuf = await imageLimit(() =>
            withRetries(() => ai.generateIllustrationBuffer(geminiApiKey, assembled, geminiSize, refs), {
              isImageCall: true
            })
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
          const storagePath = `users/${userId}/bookVersions/${jobId}/illustration_${entry.id}.png`;
          const { url } = await uploadPngWithDownloadURL(storagePath, imageBuf);

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
          // Capture every diagnostic field we can pull off the error so we
          // never have to guess again why a memory failed.  Anything that
          // can't be serialised is dropped.
          const httpStatus = e?.status || e?.statusCode || e?.response?.status || null;
          const failure = {
            stage,
            message: String(e?.message || e).slice(0, 1000),
            httpStatus,
            geminiFinishReason: e?.geminiFinishReason || null,
            geminiBlockReason: e?.geminiBlockReason || null,
            geminiTextResponse: e?.geminiTextResponse || null,
            noImageBytes: !!e?.noImageBytes,
            errorName: e?.name || null,
            at: admin.firestore.Timestamp.now()
          };
          // Strip null fields so the doc stays compact and predictable.
          for (const k of Object.keys(failure)) {
            if (failure[k] === null || failure[k] === undefined) delete failure[k];
          }
          console.error(
            JSON.stringify({
              kind: "storybook.memoryFailed",
              jobId,
              userId,
              memoryId: entry.id,
              ...failure,
              stack: e?.stack ? String(e.stack).slice(0, 2000) : undefined
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
            userId,
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
            userId,
            message: String(pitchErr?.message || pitchErr)
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
        "progress.currentStatus": "AI complete — open app to finalize",
        lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (e) {
      console.error(
        JSON.stringify({
          kind: "storybook.fatal",
          jobId,
          userId,
          message: String(e?.message || e),
          stack: e?.stack ? String(e.stack).slice(0, 2000) : null
        })
      );
      await ref.update({
        status: "failed",
        error: `Cloud worker crashed: ${String(e?.message || e).slice(0, 500)}`,
        lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
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
