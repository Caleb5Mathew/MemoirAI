const crypto = require("crypto");

const REVENUECAT_PUBLIC_API_KEY = "appl_HTtNKyhVPddJOKrcqGCnWtvZcto";
const PAID_PAGE_LIMIT = 100;
const MAX_PAGES_PER_JOB = 9;
// The app offers three preview images plus one one-time tutorial image. The
// server caps the combined lifetime allowance so a modified client cannot
// exceed what the product promises.
const FREE_PAGE_LIMIT = 4;
const GLOBAL_DAILY_PAGE_LIMIT = 500;
const ACTIVE_LEASE_MS = 20 * 60 * 1000;
const WORKER_HEARTBEAT_STALE_MS = 2 * 60 * 1000;
const MAX_WORKER_ATTEMPTS = 3;
const STORYBOOK_ADMISSION_VERSION = 1;
const SUBJECT_PHOTO_MAX_BYTES = 5 * 1024 * 1024;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const JOB_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

function paidStorybookUsagePeriod(date) {
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) {
    throw new Error("valid usage date is required");
  }
  const year = date.getUTCFullYear();
  const monthIndex = date.getUTCMonth();
  const month = String(monthIndex + 1).padStart(2, "0");
  return {
    periodKey: `paid_${year}${month}`,
    resetAt: new Date(Date.UTC(year, monthIndex + 1, 1, 0, 0, 0, 0))
  };
}

function requireString(value, field, maxLength, { allowEmpty = true } = {}) {
  const stringValue = String(value ?? "").trim();
  if ((!allowEmpty && !stringValue) || stringValue.length > maxLength) {
    throw new Error(`invalid ${field}`);
  }
  return stringValue;
}

function sanitizeStorybookJobPayload(input, userId, jobId) {
  if (!JOB_ID_PATTERN.test(jobId)) throw new Error("invalid jobId");
  const profileId = requireString(input?.profileId, "profileId", 36, { allowEmpty: false });
  if (!UUID_PATTERN.test(profileId)) throw new Error("invalid profileId");
  if (String(input?.bookVersionId || jobId) !== jobId) throw new Error("bookVersionId mismatch");

  const pageCountTarget = Number(input?.pageCountTarget);
  if (!Number.isInteger(pageCountTarget) || pageCountTarget < 1 || pageCountTarget > MAX_PAGES_PER_JOB) {
    throw new Error("invalid pageCountTarget");
  }

  const pinnedMemoryIds = Array.isArray(input?.pinnedMemoryIds) ? input.pinnedMemoryIds : [];
  if (pinnedMemoryIds.length > MAX_PAGES_PER_JOB || pinnedMemoryIds.some((id) => !UUID_PATTERN.test(String(id)))) {
    throw new Error("invalid pinnedMemoryIds");
  }

  const subjectPhotoStoragePath = requireString(
    input?.subjectPhotoStoragePath,
    "subjectPhotoStoragePath",
    220
  );
  const expectedPhotoPath = `users/${userId}/profiles/${profileId.toLowerCase()}/subjectPhoto.jpg`;
  if (subjectPhotoStoragePath && subjectPhotoStoragePath !== expectedPhotoPath) {
    throw new Error("invalid subjectPhotoStoragePath");
  }

  const styleReferencePreset = requireString(
    input?.styleReferencePreset || "normal",
    "styleReferencePreset",
    10,
    { allowEmpty: false }
  );
  if (!["normal", "ref1", "ref2"].includes(styleReferencePreset)) {
    throw new Error("invalid styleReferencePreset");
  }

  const payload = {
    profileId,
    bookVersionId: jobId,
    artStyle: requireString(input?.artStyle || "kidsBook", "artStyle", 40, { allowEmpty: false }),
    pageCountTarget,
    profileName: requireString(input?.profileName, "profileName", 100),
    profileEthnicity: requireString(input?.profileEthnicity, "profileEthnicity", 100),
    customArtStyleText: requireString(input?.customArtStyleText, "customArtStyleText", 1_000),
    styleReferencePreset,
    gender: requireString(input?.gender, "gender", 80),
    otherDetails: requireString(input?.otherDetails, "otherDetails", 5_000),
    faceDescription: requireString(input?.faceDescription, "faceDescription", 5_000),
    status: "queued",
    clientVersion: Number(input?.clientVersion) || 0,
    region: "us-central1",
    pinnedMemoryIds: pinnedMemoryIds.map(String)
  };
  if (subjectPhotoStoragePath) payload.subjectPhotoStoragePath = subjectPhotoStoragePath;
  return payload;
}

function isAdmittedStorybookJob(data) {
  return data?.admissionVersion === STORYBOOK_ADMISSION_VERSION &&
    typeof data?.requestHash === "string" &&
    /^[0-9a-f]{64}$/.test(data.requestHash);
}

async function claimStorybookWorkerJob({
  db,
  jobRef,
  userId,
  jobId,
  serverTimestamp,
  timestampFromDate,
  now = new Date()
}) {
  const activeRef = db.collection("users").doc(userId).collection("aiUsage").doc("storybook_active");
  const deletionRef = db.collection("accountDeletionRequests").doc(userId);
  return db.runTransaction(async (transaction) => {
    const [snapshot, active, deletion] = await Promise.all([
      transaction.get(jobRef),
      transaction.get(activeRef),
      transaction.get(deletionRef)
    ]);
    if (!snapshot.exists) return { action: "missing" };
    const data = snapshot.data() || {};
    if (deletion.exists) {
      transaction.delete(activeRef);
      transaction.update(jobRef, {
        status: "failed",
        error: "Account deletion is in progress.",
        updatedAt: serverTimestamp()
      });
      return { action: "account_deleting", data };
    }
    const activeData = active.data() || {};
    const hasMatchingServerLease = active.exists &&
      activeData.admissionVersion === STORYBOOK_ADMISSION_VERSION &&
      activeData.jobId === jobId &&
      activeData.requestHash === data.requestHash;
    if (!isAdmittedStorybookJob(data) || !hasMatchingServerLease) {
      transaction.update(jobRef, {
        status: "failed",
        error: "Storybook job was not admitted by the server.",
        updatedAt: serverTimestamp()
      });
      return { action: "rejected", data };
    }
    const terminalStatuses = ["aiComplete", "complete", "failed", "dismissedFailed"];
    if (terminalStatuses.includes(data.status)) {
      return { action: "skip", status: data.status, data };
    }

    const attemptCount = Math.max(0, Number(data.workerAttemptCount || 0));
    if (data.status !== "queued") {
      const heartbeat = data.lastHeartbeatAt?.toDate?.();
      const heartbeatIsFresh = heartbeat instanceof Date &&
        now.getTime() - heartbeat.getTime() < WORKER_HEARTBEAT_STALE_MS;
      if (heartbeatIsFresh) {
        return { action: "retry_later", status: data.status, data };
      }
      if (attemptCount >= MAX_WORKER_ATTEMPTS) {
        transaction.update(jobRef, {
          status: "failed",
          error: "Cloud generation was interrupted repeatedly. Please try again.",
          updatedAt: serverTimestamp()
        });
        return { action: "attempts_exhausted", status: data.status, data };
      }
    }

    const nextAttemptCount = attemptCount + 1;
    if (timestampFromDate) {
      transaction.set(activeRef, {
        leaseExpiresAt: timestampFromDate(new Date(now.getTime() + ACTIVE_LEASE_MS)),
        updatedAt: serverTimestamp()
      }, { merge: true });
    }
    transaction.update(jobRef, {
      status: "ranking",
      workerAttemptCount: nextAttemptCount,
      rankingStartedAt: serverTimestamp(),
      lastHeartbeatAt: serverTimestamp(),
      updatedAt: serverTimestamp()
    });
    return { action: "claimed", data };
  });
}

function validateSubjectPhotoPathForWorker({ userId, profileId, storagePath }) {
  const normalizedProfileId = String(profileId || "").trim().toLowerCase();
  const expectedPath = `users/${userId}/profiles/${normalizedProfileId}/subjectPhoto.jpg`;
  if (!UUID_PATTERN.test(normalizedProfileId) || storagePath !== expectedPath) {
    throw new Error("invalid subject photo storage path");
  }
  return expectedPath;
}

function validateSubjectPhotoForWorker({ userId, profileId, storagePath, metadata }) {
  const expectedPath = validateSubjectPhotoPathForWorker({ userId, profileId, storagePath });
  const contentType = String(metadata?.contentType || "").split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "image/jpeg") throw new Error("invalid subject photo content type");
  const size = Number(metadata?.size);
  if (!Number.isSafeInteger(size) || size <= 0 || size > SUBJECT_PHOTO_MAX_BYTES) {
    throw new Error("invalid subject photo size");
  }
  const generation = String(metadata?.generation || "").trim();
  if (!generation) throw new Error("missing subject photo generation");
  return { expectedPath, size, generation };
}

async function releaseStorybookActiveLease({ db, userId, jobId }) {
  const activeRef = db.collection("users").doc(userId).collection("aiUsage").doc("storybook_active");
  return db.runTransaction(async (transaction) => {
    const active = await transaction.get(activeRef);
    if (!active.exists || active.data()?.jobId !== jobId) return false;
    transaction.delete(activeRef);
    return true;
  });
}

function activeRevenueCatEntitlement(response, now = new Date()) {
  const entitlements = response?.subscriber?.entitlements || {};
  const entitlement = entitlements.image_generation;
  if (!entitlement) return null;
  if (!entitlement.expires_date) return entitlement;
  const expiresAt = new Date(entitlement.expires_date);
  return Number.isFinite(expiresAt.getTime()) && expiresAt > now ? entitlement : null;
}

function countSuccessfulStorybookPages(data) {
  return Object.values(data?.memoryResults || {}).filter(
    (result) => result && typeof result.illustrationStoragePath === "string" &&
      result.illustrationStoragePath.trim()
  ).length;
}

function storybookReservationCharges(data) {
  const reservedPages = Math.max(0, Number(data?.reservedPageCount || 0));
  const successfulPages = countSuccessfulStorybookPages(data);
  const failedPages = Object.keys(data?.memoryFailures || {}).length;
  const completedPages = Math.max(0, Number(data?.progress?.completedMemoryCount || 0));
  return {
    userPages: Math.min(reservedPages, successfulPages),
    globalPages: Math.min(reservedPages, Math.max(successfulPages + failedPages, completedPages))
  };
}

async function settleStorybookReservation({ db, jobRef, userId, serverTimestamp }) {
  return db.runTransaction(async (transaction) => {
    const jobSnapshot = await transaction.get(jobRef);
    if (!jobSnapshot.exists) return { status: "missing" };
    const data = jobSnapshot.data() || {};
    if (data.reservationState !== "reserved") return { status: "already-settled" };
    if (!["aiComplete", "complete", "failed", "dismissedFailed"].includes(data.status)) {
      return { status: "not-terminal" };
    }

    const usageDocumentId = String(data.usageDocumentId || "");
    const globalUsageDocumentId = String(data.globalUsageDocumentId || "");
    if (!usageDocumentId || !globalUsageDocumentId) {
      throw new Error("reserved storybook job is missing usage document identifiers");
    }

    const usageRef = db.collection("users").doc(userId).collection("aiUsage").doc(usageDocumentId);
    const globalRef = db.collection("globalAIUsage").doc(globalUsageDocumentId);
    const [usageSnapshot, globalSnapshot] = await Promise.all([
      transaction.get(usageRef),
      transaction.get(globalRef)
    ]);
    const reservedPages = Math.max(0, Number(data.reservedPageCount || 0));
    const charges = storybookReservationCharges(data);
    const userReservedPages = Math.max(0, Number(usageSnapshot.data()?.reservedPages || 0));
    const globalReservedPages = Math.max(0, Number(globalSnapshot.data()?.reservedPages || 0));

    transaction.set(usageRef, {
      reservedPages: Math.max(0, userReservedPages - reservedPages + charges.userPages),
      updatedAt: serverTimestamp()
    }, { merge: true });
    transaction.set(globalRef, {
      reservedPages: Math.max(0, globalReservedPages - reservedPages + charges.globalPages),
      updatedAt: serverTimestamp()
    }, { merge: true });
    transaction.update(jobRef, {
      reservationState: "settled",
      settledUserPages: charges.userPages,
      settledGlobalPages: charges.globalPages,
      reservationSettledAt: serverTimestamp(),
      updatedAt: serverTimestamp()
    });
    return { status: "settled", ...charges };
  });
}

async function fetchRevenueCatEntitlement(userId, fetchImpl = fetch) {
  const response = await fetchImpl(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
    {
      headers: { Authorization: `Bearer ${REVENUECAT_PUBLIC_API_KEY}` },
      signal: AbortSignal.timeout(8_000)
    }
  );
  if (!response.ok) throw new Error(`revenuecat ${response.status}`);
  return activeRevenueCatEntitlement(await response.json());
}

async function fetchLegacyRevenueCatEntitlement(db, userId, fetchImpl = fetch) {
  const currentEntitlement = await fetchRevenueCatEntitlement(userId, fetchImpl);
  if (currentEntitlement) return currentEntitlement;

  const userSnapshot = await db.collection("users").doc(userId).get();
  const legacyUserId = String(userSnapshot.data()?.rcUserId || "").trim();
  if (!UUID_PATTERN.test(legacyUserId) || legacyUserId === userId) return null;
  return fetchRevenueCatEntitlement(legacyUserId, fetchImpl);
}

async function admitLegacyStorybookJob({
  db,
  jobRef,
  userId,
  jobId,
  serverTimestamp,
  timestampFromDate,
  fetchImpl = fetch,
  minimumClientVersion = 2,
  now = new Date()
}) {
  const initial = await jobRef.get();
  if (!initial.exists) return { status: "missing" };
  const initialData = initial.data() || {};
  if (isAdmittedStorybookJob(initialData)) return { status: "existing" };

  let payload;
  try {
    payload = sanitizeStorybookJobPayload(initialData, userId, jobId);
  } catch (error) {
    error.permanent = true;
    throw error;
  }
  payload.clientVersion = Math.max(minimumClientVersion, Number(payload.clientVersion) || 0);
  const requestHash = stableHash(payload);

  const entitlement = await fetchLegacyRevenueCatEntitlement(db, userId, fetchImpl);
  const isPaid = Boolean(entitlement);
  if (!isPaid && payload.pageCountTarget > FREE_PAGE_LIMIT) {
    const error = new Error("A subscription is required for this book size.");
    error.permanent = true;
    throw error;
  }

  const dayKey = now.toISOString().slice(0, 10);
  const paidPeriod = isPaid ? paidStorybookUsagePeriod(now) : null;
  const periodKey = paidPeriod?.periodKey || "free_lifetime";
  const userRef = db.collection("users").doc(userId);
  const activeRef = userRef.collection("aiUsage").doc("storybook_active");
  const usageRef = userRef.collection("aiUsage").doc(`storybook_${periodKey}`);
  const globalRef = db.collection("globalAIUsage").doc(`storybook_${dayKey}`);
  const deletionRef = db.collection("accountDeletionRequests").doc(userId);

  return db.runTransaction(async (transaction) => {
    const [job, active, usage, globalUsage, deletion] = await Promise.all([
      transaction.get(jobRef),
      transaction.get(activeRef),
      transaction.get(usageRef),
      transaction.get(globalRef),
      transaction.get(deletionRef)
    ]);
    if (!job.exists) return { status: "missing" };
    if (isAdmittedStorybookJob(job.data())) return { status: "existing" };
    if (deletion.exists) {
      const error = new Error("This account is being deleted.");
      error.permanent = true;
      throw error;
    }
    const currentPayload = sanitizeStorybookJobPayload(job.data() || {}, userId, jobId);
    currentPayload.clientVersion = Math.max(
      minimumClientVersion,
      Number(currentPayload.clientVersion) || 0
    );
    if (stableHash(currentPayload) !== requestHash) {
      throw new Error("Legacy storybook job changed during admission.");
    }

    const activeData = active.data() || {};
    const leaseExpiresAt = activeData.leaseExpiresAt?.toDate?.();
    if (active.exists && activeData.jobId !== jobId && leaseExpiresAt && leaseExpiresAt > now) {
      const error = new Error("Another storybook is already being generated.");
      error.permanent = true;
      throw error;
    }
    const perUserLimit = isPaid ? PAID_PAGE_LIMIT : FREE_PAGE_LIMIT;
    const usedPages = Number(usage.data()?.reservedPages || 0);
    const globalPages = Number(globalUsage.data()?.reservedPages || 0);
    if (usedPages + payload.pageCountTarget > perUserLimit ||
        globalPages + payload.pageCountTarget > GLOBAL_DAILY_PAGE_LIMIT) {
      const error = new Error("This generation allowance has been used.");
      error.permanent = true;
      throw error;
    }

    transaction.set(usageRef, {
      reservedPages: usedPages + payload.pageCountTarget,
      limit: perUserLimit,
      periodKey,
      resetAt: paidPeriod ? timestampFromDate(paidPeriod.resetAt) : null,
      updatedAt: serverTimestamp()
    }, { merge: true });
    transaction.set(globalRef, {
      reservedPages: globalPages + payload.pageCountTarget,
      limit: GLOBAL_DAILY_PAGE_LIMIT,
      dayKey,
      updatedAt: serverTimestamp()
    }, { merge: true });
    transaction.set(activeRef, {
      jobId,
      admissionVersion: STORYBOOK_ADMISSION_VERSION,
      requestHash,
      leaseExpiresAt: timestampFromDate(new Date(now.getTime() + ACTIVE_LEASE_MS)),
      updatedAt: serverTimestamp()
    });
    transaction.update(jobRef, {
      ...payload,
      admissionVersion: STORYBOOK_ADMISSION_VERSION,
      entitlementKind: isPaid ? "paid" : "freePreview",
      reservationState: "reserved",
      reservedPageCount: payload.pageCountTarget,
      usageDocumentId: usageRef.path.split("/").pop(),
      globalUsageDocumentId: globalRef.path.split("/").pop(),
      requestHash,
      updatedAt: serverTimestamp(),
      progress: {
        completedMemoryCount: 0,
        totalMemories: 0,
        currentStatus: "Queued…"
      },
      memoryResults: {},
      skippedMemoryIds: []
    });
    return { status: "admitted", requestHash };
  });
}

function stableHash(value) {
  const ordered = Object.keys(value).sort().reduce((result, key) => {
    result[key] = value[key];
    return result;
  }, {});
  return crypto.createHash("sha256").update(JSON.stringify(ordered)).digest("hex");
}

function createStorybookJobHandler({
  db,
  serverTimestamp,
  timestampFromDate,
  HttpsError,
  fetchImpl = fetch,
  nowDate = () => new Date()
}) {
  return async (request) => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Must be signed in");
    const userId = request.auth.uid;
    const jobId = String(request.data?.jobId || "").trim();

    let payload;
    try {
      payload = sanitizeStorybookJobPayload(request.data?.job, userId, jobId);
    } catch (error) {
      throw new HttpsError("invalid-argument", String(error.message || error));
    }

    const userRef = db.collection("users").doc(userId);
    const jobRef = userRef.collection("storybookJobs").doc(jobId);
    const requestHash = stableHash(payload);
    const replaySnapshot = await jobRef.get();
    if (replaySnapshot.exists) {
      const existingData = replaySnapshot.data() || {};
      if (
        existingData.admissionVersion === STORYBOOK_ADMISSION_VERSION &&
        existingData.requestHash === requestHash
      ) {
        return { status: "existing", jobId };
      }
      throw new HttpsError("already-exists", "A different job already uses this identifier.");
    }

    let entitlement;
    try {
      entitlement = await fetchRevenueCatEntitlement(userId, fetchImpl);
    } catch (error) {
      console.error("storybook RevenueCat verification failed", String(error?.message || error));
      throw new HttpsError("unavailable", "Subscription verification is temporarily unavailable.");
    }

    const isPaid = Boolean(entitlement);
    if (!isPaid && payload.pageCountTarget > FREE_PAGE_LIMIT) {
      throw new HttpsError("permission-denied", "A subscription is required for this book size.");
    }

    const now = nowDate();
    const dayKey = now.toISOString().slice(0, 10);
    const paidPeriod = isPaid ? paidStorybookUsagePeriod(now) : null;
    const periodKey = paidPeriod?.periodKey || "free_lifetime";
    const activeRef = userRef.collection("aiUsage").doc("storybook_active");
    const usageRef = userRef.collection("aiUsage").doc(`storybook_${periodKey}`);
    const globalRef = db.collection("globalAIUsage").doc(`storybook_${dayKey}`);
    const deletionRef = db.collection("accountDeletionRequests").doc(userId);

    const result = await db.runTransaction(async (transaction) => {
      const [existing, active, usage, globalUsage, deletion] = await Promise.all([
        transaction.get(jobRef),
        transaction.get(activeRef),
        transaction.get(usageRef),
        transaction.get(globalRef),
        transaction.get(deletionRef)
      ]);
      if (deletion.exists) throw new HttpsError("failed-precondition", "This account is being deleted.");
      if (existing.exists) {
        if (
          existing.data()?.admissionVersion === STORYBOOK_ADMISSION_VERSION &&
          existing.data()?.requestHash === requestHash
        ) {
          return { status: "existing" };
        }
        throw new HttpsError("already-exists", "A different job already uses this identifier.");
      }

      const activeData = active.data() || {};
      const leaseExpiresAt = activeData.leaseExpiresAt?.toDate?.();
      if (active.exists && activeData.jobId !== jobId && leaseExpiresAt && leaseExpiresAt > now) {
        throw new HttpsError("resource-exhausted", "Another storybook is already being generated.");
      }

      const perUserLimit = isPaid ? PAID_PAGE_LIMIT : FREE_PAGE_LIMIT;
      const usedPages = Number(usage.data()?.reservedPages || 0);
      const globalPages = Number(globalUsage.data()?.reservedPages || 0);
      if (usedPages + payload.pageCountTarget > perUserLimit) {
        throw new HttpsError("resource-exhausted", "This generation allowance has been used.");
      }
      if (globalPages + payload.pageCountTarget > GLOBAL_DAILY_PAGE_LIMIT) {
        throw new HttpsError("resource-exhausted", "Storybook generation is at its daily capacity.");
      }

      const nextReservedPages = usedPages + payload.pageCountTarget;
      transaction.set(usageRef, {
        reservedPages: nextReservedPages,
        limit: perUserLimit,
        periodKey,
        resetAt: paidPeriod ? timestampFromDate(paidPeriod.resetAt) : null,
        updatedAt: serverTimestamp()
      }, { merge: true });
      transaction.set(globalRef, {
        reservedPages: globalPages + payload.pageCountTarget,
        limit: GLOBAL_DAILY_PAGE_LIMIT,
        dayKey,
        updatedAt: serverTimestamp()
      }, { merge: true });
      transaction.set(activeRef, {
        jobId,
        admissionVersion: STORYBOOK_ADMISSION_VERSION,
        requestHash,
        leaseExpiresAt: timestampFromDate(new Date(now.getTime() + ACTIVE_LEASE_MS)),
        updatedAt: serverTimestamp()
      });
      transaction.create(jobRef, {
        ...payload,
        admissionVersion: STORYBOOK_ADMISSION_VERSION,
        entitlementKind: isPaid ? "paid" : "freePreview",
        reservationState: "reserved",
        reservedPageCount: payload.pageCountTarget,
        usageDocumentId: usageRef.path.split("/").pop(),
        globalUsageDocumentId: globalRef.path.split("/").pop(),
        requestHash,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        progress: {
          completedMemoryCount: 0,
          totalMemories: 0,
          currentStatus: "Queued…"
        },
        memoryResults: {},
        skippedMemoryIds: []
      });
      return {
        status: "queued",
        allowanceRemaining: Math.max(0, perUserLimit - nextReservedPages),
        allowanceResetAt: paidPeriod?.resetAt.toISOString() || null
      };
    });

    return { ...result, jobId };
  };
}

module.exports = {
  FREE_PAGE_LIMIT,
  MAX_PAGES_PER_JOB,
  MAX_WORKER_ATTEMPTS,
  STORYBOOK_ADMISSION_VERSION,
  WORKER_HEARTBEAT_STALE_MS,
  SUBJECT_PHOTO_MAX_BYTES,
  activeRevenueCatEntitlement,
  admitLegacyStorybookJob,
  claimStorybookWorkerJob,
  createStorybookJobHandler,
  fetchLegacyRevenueCatEntitlement,
  isAdmittedStorybookJob,
  paidStorybookUsagePeriod,
  releaseStorybookActiveLease,
  settleStorybookReservation,
  storybookReservationCharges,
  sanitizeStorybookJobPayload,
  validateSubjectPhotoPathForWorker,
  validateSubjectPhotoForWorker
};
