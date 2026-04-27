/**
 * Firestore-triggered storybook AI generation worker.
 */

const admin = require("firebase-admin");
const crypto = require("crypto");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const pLimit = require("p-limit");
const { createStorybookAI } = require("./storybookAI");

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
      artStyle: data.artStyle,
      hasSubjectPhoto: !!data.subjectPhotoStoragePath
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

    try {
      await ref.update({
        status: "ranking",
        lastHeartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      const profileId = String(data.profileId || "");
      const pageCountTarget = Math.max(1, parseInt(String(data.pageCountTarget || "1"), 10) || 1);
      const artStyle = String(data.artStyle || "kidsBook");
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

      logJob("storybook.rankingStart", { input: memories.length, target: pageCountTarget });
      const ranked = await ai.rankMemoriesWithLLM(memories, pageCountTarget);
      logJob("storybook.rankingDone", { ranked: ranked.length });
      const ages = await Promise.all(ranked.map((m) => ai.extractAge(String(m.transcription || ""))));
      const ordered = ranked
        .map((m, i) => ({ m, age: ages[i] ?? 999 }))
        .sort((a, b) => a.age - b.age)
        .map((x) => x.m);

      const orderedMemoryIds = ordered.map((m) => m.id);

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
          const characterContext = ai.buildCharacterContextFromDetails(entry.characterDetails, job);
          const sceneDescription = await withRetries(() => ai.extractVisualScene(raw, characterContext));

          stage = "title";
          phaseLog(entry.id, stage);
          const extracted = await withRetries(() => ai.extractTitleAndCharacters(raw, characterContext));

          stage = "narrator";
          const narrator = ai.inferNarratorPresence(raw, entry.chapter, job.profileName);
          const includeNarrator = narrator.shouldAttachHeadshot;

          stage = "promptAssembly";
          const characterList = ai.buildCharacterList(entry, job, sceneDescription, includeNarrator);
          const assembled = ai.assembleFinalPrompt(
            raw,
            characterList,
            narrator.presence,
            sceneDescription,
            artStyle,
            job.customArtStyleText,
            !!headshotBuf,
            job,
            stylePreset
          );

          const refs = [];
          if (includeNarrator && headshotBuf) refs.push(headshotBuf);
          if (styleRefBuf) refs.push(styleRefBuf);

          stage = "image";
          phaseLog(entry.id, stage, {
            promptLen: assembled.length,
            includesNarrator: includeNarrator,
            hasHeadshot: !!headshotBuf,
            hasStyleRef: !!styleRefBuf,
            artStyle
          });
          const geminiSize = artStyle === "kidsBook" ? "4:3" : "1792x1024";
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
            extractedTitle: extracted.title,
            illustrationBarTitle,
            completedAt: admin.firestore.Timestamp.now()
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
      const pitch = (await ai.generateBackCoverPitch(pitchPrompt)) || "";

      logJob("storybook.aiComplete", {
        successCount,
        failureCount: Object.keys(finalFailures).length,
        pitchLen: (pitch || "").length
      });

      await ref.update({
        status: "aiComplete",
        backCoverPitch: pitch,
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
