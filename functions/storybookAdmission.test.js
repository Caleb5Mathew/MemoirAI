const assert = require("assert");
const {
  admitLegacyStorybookJob,
  activeRevenueCatEntitlement,
  claimStorybookWorkerJob,
  createStorybookJobHandler,
  FREE_PAGE_LIMIT,
  fetchLegacyRevenueCatEntitlement,
  isAdmittedStorybookJob,
  releaseStorybookActiveLease,
  settleStorybookReservation,
  storybookReservationCharges,
  sanitizeStorybookJobPayload,
  validateSubjectPhotoPathForWorker,
  validateSubjectPhotoForWorker
} = require("./storybookAdmission");

const profileId = "11111111-1111-4111-8111-111111111111";
const memoryId = "22222222-2222-4222-8222-222222222222";
const base = {
  profileId,
  bookVersionId: "job_1",
  pageCountTarget: 2,
  pinnedMemoryIds: [memoryId],
  subjectPhotoStoragePath: `users/user-1/profiles/${profileId}/subjectPhoto.jpg`
};

assert.strictEqual(sanitizeStorybookJobPayload(base, "user-1", "job_1").status, "queued");
assert.throws(
  () => sanitizeStorybookJobPayload({ ...base, pageCountTarget: 101 }, "user-1", "job_1"),
  /pageCountTarget/
);
assert.throws(
  () => sanitizeStorybookJobPayload({
    ...base,
    subjectPhotoStoragePath: `users/other/profiles/${profileId}/subjectPhoto.jpg`
  }, "user-1", "job_1"),
  /subjectPhotoStoragePath/
);
assert.throws(
  () => sanitizeStorybookJobPayload({ ...base, pinnedMemoryIds: ["not-a-uuid"] }, "user-1", "job_1"),
  /pinnedMemoryIds/
);

const now = new Date("2026-08-27T12:00:00Z");
assert.ok(activeRevenueCatEntitlement({ subscriber: { entitlements: {
  image_generation: { expires_date: "2026-09-27T12:00:00Z" }
} } }, now));
assert.strictEqual(activeRevenueCatEntitlement({ subscriber: { entitlements: {
  image_generation: { expires_date: "2026-07-27T12:00:00Z" }
} } }, now), null);
assert.strictEqual(activeRevenueCatEntitlement({ subscriber: { entitlements: {
  unrelated: { expires_date: "2026-09-27T12:00:00Z" }
} } }, now), null);
assert.strictEqual(FREE_PAGE_LIMIT, 4);
assert.deepStrictEqual(storybookReservationCharges({
  reservedPageCount: 4,
  memoryResults: { a: { illustrationStoragePath: "users/u/a.png" } },
  memoryFailures: { b: {}, c: {} },
  progress: { completedMemoryCount: 3 }
}), { userPages: 1, globalPages: 3 });

class FakeSnapshot {
  constructor(value) {
    this.value = value;
    this.exists = value !== undefined;
  }
  data() { return this.value; }
}

class FakeDocumentReference {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }
  collection(name) { return new FakeCollectionReference(this.db, `${this.path}/${name}`); }
  async get() { return new FakeSnapshot(this.db.rows.get(this.path)); }
}

class FakeCollectionReference {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }
  doc(id) { return new FakeDocumentReference(this.db, `${this.path}/${id}`); }
}

class FakeFirestore {
  constructor() {
    this.rows = new Map();
  }
  collection(name) { return new FakeCollectionReference(this, name); }
  async runTransaction(callback) {
    const writes = [];
    const transaction = {
      get: async (ref) => new FakeSnapshot(this.rows.get(ref.path)),
      set: (ref, value, options) => writes.push({ kind: "set", ref, value, options }),
      create: (ref, value) => writes.push({ kind: "create", ref, value }),
      update: (ref, value) => writes.push({ kind: "update", ref, value }),
      delete: (ref) => writes.push({ kind: "delete", ref })
    };
    const result = await callback(transaction);
    for (const write of writes) {
      if (write.kind === "delete") {
        this.rows.delete(write.ref.path);
        continue;
      }
      if (write.kind === "create" && this.rows.has(write.ref.path)) throw new Error("already exists");
      const prior = this.rows.get(write.ref.path) || {};
      this.rows.set(
        write.ref.path,
        write.kind === "update" || write.options?.merge ? { ...prior, ...write.value } : write.value
      );
    }
    return result;
  }
}

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const serverTimestamp = () => "SERVER_TIMESTAMP";
const timestampFromDate = (date) => ({ toDate: () => date });

(async () => {
  const db = new FakeFirestore();
  let revenueCatCalls = 0;
  const handler = createStorybookJobHandler({
    db,
    serverTimestamp,
    timestampFromDate,
    HttpsError: FakeHttpsError,
    fetchImpl: async () => {
      revenueCatCalls += 1;
      if (revenueCatCalls > 1) throw new Error("Replay must not call RevenueCat");
      return {
        ok: true,
        json: async () => ({ subscriber: { entitlements: {
          image_generation: { expires_date: "2099-01-01T00:00:00Z" }
        } } })
      };
    }
  });
  const request = {
    auth: { uid: "user-1" },
    data: { jobId: "job_1", job: { ...base, clientVersion: 2 } }
  };
  assert.deepStrictEqual(await handler(request), { status: "queued", jobId: "job_1" });
  const jobPath = "users/user-1/storybookJobs/job_1";
  assert.strictEqual(db.rows.get(jobPath).admissionVersion, 1);
  assert.strictEqual(db.rows.get(jobPath).reservationState, "reserved");
  assert.ok(isAdmittedStorybookJob(db.rows.get(jobPath)));
  const usageBeforeReplay = Array.from(db.rows.entries())
    .filter(([path]) => path.includes("/aiUsage/storybook_paid_"))[0][1].reservedPages;

  assert.deepStrictEqual(await handler(request), { status: "existing", jobId: "job_1" });
  assert.strictEqual(revenueCatCalls, 1);
  const usageAfterReplay = Array.from(db.rows.entries())
    .filter(([path]) => path.includes("/aiUsage/storybook_paid_"))[0][1].reservedPages;
  assert.strictEqual(usageAfterReplay, usageBeforeReplay);
  await assert.rejects(
    () => handler({ ...request, data: { ...request.data, job: { ...request.data.job, pageCountTarget: 3 } } }),
    (error) => error.code === "already-exists"
  );

  const activePath = "users/user-1/aiUsage/storybook_active";
  assert.strictEqual(db.rows.get(activePath).jobId, "job_1");
  assert.strictEqual(await releaseStorybookActiveLease({ db, userId: "user-1", jobId: "other" }), false);
  assert.ok(db.rows.has(activePath));
  assert.strictEqual(await releaseStorybookActiveLease({ db, userId: "user-1", jobId: "job_1" }), true);
  assert.ok(!db.rows.has(activePath));

  db.rows.set(jobPath, {
    ...db.rows.get(jobPath),
    status: "aiComplete",
    memoryResults: {
      [memoryId]: { illustrationStoragePath: `users/user-1/storybooks/job_1/${memoryId}.png` }
    },
    progress: { completedMemoryCount: 2 }
  });
  const paidUsageEntry = Array.from(db.rows.entries())
    .find(([path]) => path.includes("/aiUsage/storybook_paid_"));
  assert.ok(paidUsageEntry);
  const globalUsageEntry = Array.from(db.rows.entries())
    .find(([path]) => path.startsWith("globalAIUsage/storybook_"));
  assert.ok(globalUsageEntry);
  assert.deepStrictEqual(await settleStorybookReservation({
    db,
    jobRef: db.collection("users").doc("user-1").collection("storybookJobs").doc("job_1"),
    userId: "user-1",
    serverTimestamp
  }), { status: "settled", userPages: 1, globalPages: 2 });
  assert.strictEqual(db.rows.get(paidUsageEntry[0]).reservedPages, 1);
  assert.strictEqual(db.rows.get(globalUsageEntry[0]).reservedPages, 2);
  assert.strictEqual((await settleStorybookReservation({
    db,
    jobRef: db.collection("users").doc("user-1").collection("storybookJobs").doc("job_1"),
    userId: "user-1",
    serverTimestamp
  })).status, "already-settled");
  assert.strictEqual(db.rows.get(paidUsageEntry[0]).reservedPages, 1);

  const freeDb = new FakeFirestore();
  const freeHandler = createStorybookJobHandler({
    db: freeDb,
    serverTimestamp,
    timestampFromDate,
    HttpsError: FakeHttpsError,
    fetchImpl: async () => ({ ok: true, json: async () => ({ subscriber: { entitlements: {} } }) })
  });
  const freeRequest = (jobId, pageCountTarget) => ({
    auth: { uid: "free-user" },
    data: {
      jobId,
      job: {
        ...base,
        bookVersionId: jobId,
        pageCountTarget,
        subjectPhotoStoragePath: "",
        clientVersion: 2
      }
    }
  });
  await freeHandler(freeRequest("free-1", 3));
  await releaseStorybookActiveLease({ db: freeDb, userId: "free-user", jobId: "free-1" });
  await freeHandler(freeRequest("free-2", 1));
  await releaseStorybookActiveLease({ db: freeDb, userId: "free-user", jobId: "free-2" });
  await assert.rejects(
    () => freeHandler(freeRequest("free-3", 1)),
    (error) => error.code === "resource-exhausted"
  );

  const legacyDb = new FakeFirestore();
  const legacyRef = legacyDb.collection("users").doc("legacy-user")
    .collection("storybookJobs").doc("legacy-job");
  legacyDb.rows.set(legacyRef.path, {
    ...base,
    bookVersionId: "legacy-job",
    subjectPhotoStoragePath: "",
    clientVersion: 0,
    status: "queued"
  });
  const legacyAdmission = await admitLegacyStorybookJob({
    db: legacyDb,
    jobRef: legacyRef,
    userId: "legacy-user",
    jobId: "legacy-job",
    serverTimestamp,
    timestampFromDate,
    fetchImpl: async () => ({ ok: true, json: async () => ({ subscriber: { entitlements: {} } }) })
  });
  assert.strictEqual(legacyAdmission.status, "admitted");
  assert.strictEqual(legacyDb.rows.get(legacyRef.path).admissionVersion, 1);
  assert.strictEqual(legacyDb.rows.get(legacyRef.path).clientVersion, 2);
  assert.strictEqual(legacyDb.rows.get(legacyRef.path).reservationState, "reserved");
  assert.ok(isAdmittedStorybookJob(legacyDb.rows.get(legacyRef.path)));

  const legacyRevenueCatId = "33333333-3333-4333-8333-333333333333";
  legacyDb.rows.set("users/legacy-paid-user", { rcUserId: legacyRevenueCatId });
  const requestedRevenueCatIds = [];
  const legacyEntitlement = await fetchLegacyRevenueCatEntitlement(
    legacyDb,
    "legacy-paid-user",
    async (url) => {
      const subscriberId = decodeURIComponent(String(url).split("/").pop());
      requestedRevenueCatIds.push(subscriberId);
      return {
        ok: true,
        json: async () => ({ subscriber: { entitlements: subscriberId === legacyRevenueCatId
          ? { image_generation: { expires_date: "2099-01-01T00:00:00Z" } }
          : {} } })
      };
    }
  );
  assert.ok(legacyEntitlement);
  assert.deepStrictEqual(requestedRevenueCatIds, ["legacy-paid-user", legacyRevenueCatId]);

  const oversizedLegacyRef = legacyDb.collection("users").doc("legacy-free-2")
    .collection("storybookJobs").doc("legacy-too-large");
  legacyDb.rows.set(oversizedLegacyRef.path, {
    ...base,
    bookVersionId: "legacy-too-large",
    pageCountTarget: FREE_PAGE_LIMIT + 1,
    subjectPhotoStoragePath: "",
    status: "queued"
  });
  await assert.rejects(
    () => admitLegacyStorybookJob({
      db: legacyDb,
      jobRef: oversizedLegacyRef,
      userId: "legacy-free-2",
      jobId: "legacy-too-large",
      serverTimestamp,
      timestampFromDate,
      fetchImpl: async () => ({ ok: true, json: async () => ({ subscriber: { entitlements: {} } }) })
    }),
    (error) => error.permanent === true
  );

  const unadmittedRef = db.collection("users").doc("user-1").collection("storybookJobs").doc("bad-job");
  db.rows.set(unadmittedRef.path, { status: "queued" });
  assert.strictEqual((await claimStorybookWorkerJob({
    db,
    jobRef: unadmittedRef,
    userId: "user-1",
    jobId: "bad-job",
    serverTimestamp
  })).action, "rejected");
  assert.strictEqual(db.rows.get(unadmittedRef.path).status, "failed");

  const forgedRef = db.collection("users").doc("user-1").collection("storybookJobs").doc("forged-job");
  db.rows.set(forgedRef.path, { admissionVersion: 1, requestHash: "b".repeat(64), status: "queued" });
  assert.strictEqual((await claimStorybookWorkerJob({
    db,
    jobRef: forgedRef,
    userId: "user-1",
    jobId: "forged-job",
    serverTimestamp
  })).action, "rejected");

  const admittedRef = db.collection("users").doc("user-1").collection("storybookJobs").doc("good-job");
  db.rows.set(admittedRef.path, { admissionVersion: 1, requestHash: "a".repeat(64), status: "queued" });
  db.rows.set(activePath, {
    admissionVersion: 1,
    requestHash: "a".repeat(64),
    jobId: "good-job",
    leaseExpiresAt: timestampFromDate(new Date("2099-01-01T00:00:00Z"))
  });
  assert.strictEqual((await claimStorybookWorkerJob({
    db,
    jobRef: admittedRef,
    userId: "user-1",
    jobId: "good-job",
    serverTimestamp,
    timestampFromDate
  })).action, "claimed");
  assert.strictEqual(db.rows.get(admittedRef.path).workerAttemptCount, 1);
  db.rows.set(admittedRef.path, {
    ...db.rows.get(admittedRef.path),
    lastHeartbeatAt: timestampFromDate(new Date("2026-08-27T12:00:00Z"))
  });
  assert.strictEqual((await claimStorybookWorkerJob({
    db,
    jobRef: admittedRef,
    userId: "user-1",
    jobId: "good-job",
    serverTimestamp,
    timestampFromDate,
    now: new Date("2026-08-27T12:01:00Z")
  })).action, "retry_later");
  assert.strictEqual((await claimStorybookWorkerJob({
    db,
    jobRef: admittedRef,
    userId: "user-1",
    jobId: "good-job",
    serverTimestamp,
    timestampFromDate,
    now: new Date("2026-08-27T12:03:00Z")
  })).action, "claimed");
  assert.strictEqual(db.rows.get(admittedRef.path).workerAttemptCount, 2);

  const deletingRef = db.collection("users").doc("deleting-user")
    .collection("storybookJobs").doc("deleting-job");
  const deletingActivePath = "users/deleting-user/aiUsage/storybook_active";
  db.rows.set(deletingRef.path, {
    admissionVersion: 1,
    requestHash: "c".repeat(64),
    status: "ranking"
  });
  db.rows.set(deletingActivePath, {
    admissionVersion: 1,
    requestHash: "c".repeat(64),
    jobId: "deleting-job",
    leaseExpiresAt: timestampFromDate(new Date("2026-08-27T11:00:00Z"))
  });
  db.rows.set("accountDeletionRequests/deleting-user", { status: "deleting" });
  assert.strictEqual((await claimStorybookWorkerJob({
    db,
    jobRef: deletingRef,
    userId: "deleting-user",
    jobId: "deleting-job",
    serverTimestamp,
    timestampFromDate,
    now: new Date("2026-08-27T12:00:00Z")
  })).action, "account_deleting");
  assert.ok(!db.rows.has(deletingActivePath));
  assert.strictEqual(db.rows.get(deletingRef.path).status, "failed");

  const photoPath = `users/user-1/profiles/${profileId}/subjectPhoto.jpg`;
  assert.strictEqual(validateSubjectPhotoPathForWorker({
    userId: "user-1",
    profileId,
    storagePath: photoPath
  }), photoPath);
  assert.deepStrictEqual(validateSubjectPhotoForWorker({
    userId: "user-1",
    profileId,
    storagePath: photoPath,
    metadata: { contentType: "image/jpeg", size: "1024", generation: "4" }
  }), { expectedPath: photoPath, size: 1024, generation: "4" });
  assert.throws(() => validateSubjectPhotoPathForWorker({
    userId: "user-1",
    profileId,
    storagePath: `users/other/profiles/${profileId}/subjectPhoto.jpg`
  }), /storage path/);
  assert.throws(() => validateSubjectPhotoForWorker({
    userId: "user-1",
    profileId,
    storagePath: photoPath,
    metadata: { contentType: "image/png", size: 1024, generation: "4" }
  }), /content type/);

  console.log("storybookAdmission.test.js: all assertions passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
