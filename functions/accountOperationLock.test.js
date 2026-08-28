const assert = require("assert");
const {
  acquireCheckoutLease,
  beginAccountDeletion,
  isActiveCheckoutLock,
  isActiveStorybookLease,
  releaseCheckoutLease
} = require("./accountOperationLock");

class FakeHttpsError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

function fakeDb(initial = {}) {
  const records = new Map(Object.entries(initial));
  const ref = (path) => ({
    path,
    collection(name) {
      return { doc(id) { return ref(`${path}/${name}/${id}`); } };
    }
  });
  return {
    records,
    collection(name) {
      return { doc(id) { return ref(`${name}/${id}`); } };
    },
    async runTransaction(work) {
      return work({
        async get(document) {
          const data = records.get(document.path);
          return { exists: data != null, data: () => data };
        },
        set(document, data, options) {
          records.set(document.path, options?.merge
            ? { ...(records.get(document.path) || {}), ...data }
            : data);
        },
        delete(document) { records.delete(document.path); }
      });
    }
  };
}

async function run() {
  assert.strictEqual(isActiveCheckoutLock({
    state: "checkout", checkoutExpiresAtMillis: 200
  }, 100), true);
  assert.strictEqual(isActiveCheckoutLock({
    state: "checkout", checkoutExpiresAtMillis: 100
  }, 100), false);
  assert.strictEqual(isActiveStorybookLease({
    jobId: "job-1", leaseExpiresAt: { toMillis: () => 200 }
  }, 100), true);
  assert.strictEqual(isActiveStorybookLease({
    jobId: "job-1", leaseExpiresAt: { toMillis: () => 100 }
  }, 100), false);

  const db = fakeDb();
  await acquireCheckoutLease({
    db,
    userId: "user-1",
    leaseId: "lease-1",
    HttpsError: FakeHttpsError,
    nowMillis: () => 100,
    leaseMillis: 50,
    serverTimestamp: () => "time"
  });
  assert.strictEqual(
    db.records.get("accountOperationLocks/user-1").checkoutExpiresAtMillis,
    150
  );

  await assert.rejects(
    beginAccountDeletion({
      db,
      userId: "user-1",
      HttpsError: FakeHttpsError,
      deletionFields: { status: "deleting" },
      nowMillis: () => 120,
      serverTimestamp: () => "time"
    }),
    (error) => error.code === "failed-precondition"
      && error.details.reason === "active-checkout"
  );

  assert.strictEqual(await releaseCheckoutLease({
    db, userId: "user-1", leaseId: "wrong"
  }), false);
  assert.strictEqual(await releaseCheckoutLease({
    db, userId: "user-1", leaseId: "lease-1"
  }), true);

  await beginAccountDeletion({
    db,
    userId: "user-1",
    HttpsError: FakeHttpsError,
    deletionFields: { status: "deleting" },
    nowMillis: () => 120,
    serverTimestamp: () => "time"
  });
  assert.strictEqual(db.records.get("accountDeletionRequests/user-1").status, "deleting");
  assert.strictEqual(db.records.get("accountOperationLocks/user-1").state, "deleting");

  const storybookDb = fakeDb({
    "users/user-2/aiUsage/storybook_active": {
      jobId: "job-2",
      leaseExpiresAt: { toMillis: () => 500 }
    }
  });
  await assert.rejects(
    beginAccountDeletion({
      db: storybookDb,
      userId: "user-2",
      HttpsError: FakeHttpsError,
      deletionFields: { status: "deleting" },
      nowMillis: () => 100,
      serverTimestamp: () => "time"
    }),
    (error) => error.code === "failed-precondition"
      && error.details.reason === "active-storybook"
  );

  await assert.rejects(
    acquireCheckoutLease({
      db,
      userId: "user-1",
      leaseId: "lease-2",
      HttpsError: FakeHttpsError,
      nowMillis: () => 200,
      serverTimestamp: () => "time"
    }),
    (error) => error.code === "failed-precondition"
  );
}

run().then(() => {
  console.log("accountOperationLock tests passed");
}).catch((error) => {
  console.error(error);
  process.exit(1);
});
