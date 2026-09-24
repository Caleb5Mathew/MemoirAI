const assert = require("node:assert/strict");
const test = require("node:test");
const {
  createEnrollGuestRecoveryHandler,
  createRecoverGuestAccountHandler,
  createRevokeGuestRecoveryHandler,
  isRecoverableGuestToken,
  normalizedRecoveryRequest,
  revokeGuestRecoveryMappings
} = require("./guestRecovery");

class FakeHttpsError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

function mergeValue(existing, value, options) {
  return options?.merge ? { ...(existing || {}), ...value } : value;
}

function createDb(seed = {}) {
  const rows = new Map(Object.entries(seed));
  const ref = (path) => ({
    path,
    async get() {
      return snapshot(path);
    },
    async set(value, options) {
      rows.set(path, mergeValue(rows.get(path), value, options));
    }
  });
  const snapshot = (path) => ({
    exists: rows.has(path),
    data: () => rows.get(path),
    ref: ref(path)
  });

  return {
    rows,
    collection(name) {
      return {
        doc(id) {
          return ref(`${name}/${id}`);
        },
        where(field, operation, value) {
          assert.equal(operation, "==");
          return {
            async get() {
              const docs = [...rows.entries()]
                .filter(([path, data]) => path.startsWith(`${name}/`) && data?.[field] === value)
                .map(([path]) => snapshot(path));
              return { docs, empty: docs.length === 0 };
            }
          };
        }
      };
    },
    async runTransaction(operation) {
      return operation({
        get: (documentRef) => documentRef.get(),
        set(documentRef, value, options) {
          rows.set(documentRef.path, mergeValue(rows.get(documentRef.path), value, options));
        }
      });
    },
    batch() {
      const writes = [];
      return {
        set(documentRef, value, options) {
          writes.push({ documentRef, value, options });
        },
        async commit() {
          for (const write of writes) {
            rows.set(
              write.documentRef.path,
              mergeValue(rows.get(write.documentRef.path), write.value, write.options)
            );
          }
        }
      };
    }
  };
}

const secret = Buffer.alloc(32, 7).toString("base64");
const anonymousToken = { firebase: { sign_in_provider: "anonymous", identities: {} } };

test("validates canonical 32-byte base64 and hashes decoded bytes", () => {
  const parsed = normalizedRecoveryRequest({ recoverySecret: secret, protocolVersion: 1 }, FakeHttpsError);
  assert.equal(parsed.secretHash.length, 64);
  assert.throws(
    () => normalizedRecoveryRequest({ recoverySecret: "short", protocolVersion: 1 }, FakeHttpsError),
    (error) => error.code === "invalid-argument"
  );
  assert.throws(
    () => normalizedRecoveryRequest({ recoverySecret: secret, protocolVersion: 2 }, FakeHttpsError),
    (error) => error.code === "invalid-argument"
  );
});

test("recognizes native anonymous and recovered memoir guest tokens only", () => {
  assert.equal(isRecoverableGuestToken(anonymousToken), true);
  assert.equal(isRecoverableGuestToken({ memoirGuest: true }), true);
  assert.equal(isRecoverableGuestToken({
    firebase: {
      sign_in_provider: "anonymous",
      identities: { "apple.com": ["linked"] }
    }
  }), false);
  assert.equal(isRecoverableGuestToken({ firebase: { sign_in_provider: "password" } }), false);
});

test("enrollment stores only the hash and is idempotent for the same guest", async () => {
  const db = createDb();
  const handler = createEnrollGuestRecoveryHandler({
    db,
    serverTimestamp: () => "time",
    HttpsError: FakeHttpsError
  });
  assert.deepEqual(await handler({
    auth: { uid: "guest-1", token: anonymousToken },
    data: { recoverySecret: secret, protocolVersion: 1 }
  }), { status: "active" });
  await handler({
    auth: { uid: "guest-1", token: anonymousToken },
    data: { recoverySecret: secret, protocolVersion: 1 }
  });

  const mappings = [...db.rows.entries()].filter(([path]) => path.startsWith("guestRecoveryMappings/"));
  assert.equal(mappings.length, 1);
  assert.equal(mappings[0][1].guestUid, "guest-1");
  assert.equal(JSON.stringify(mappings[0][1]).includes(secret), false);
});

test("enrollment rejects linked accounts and deletion markers", async () => {
  const linkedHandler = createEnrollGuestRecoveryHandler({
    db: createDb(), serverTimestamp: () => "time", HttpsError: FakeHttpsError
  });
  await assert.rejects(linkedHandler({
    auth: { uid: "linked", token: { firebase: { sign_in_provider: "password" } } },
    data: { recoverySecret: secret, protocolVersion: 1 }
  }), (error) => error.code === "failed-precondition");

  const db = createDb({ "accountDeletionRequests/guest-1": { status: "deleting" } });
  const deletedHandler = createEnrollGuestRecoveryHandler({
    db, serverTimestamp: () => "time", HttpsError: FakeHttpsError
  });
  await assert.rejects(deletedHandler({
    auth: { uid: "guest-1", token: anonymousToken },
    data: { recoverySecret: secret, protocolVersion: 1 }
  }), (error) => error.code === "failed-precondition");
});

test("recovery restores the original UID with memoirGuest claim and keeps mapping active", async () => {
  const hash = normalizedRecoveryRequest(
    { recoverySecret: secret, protocolVersion: 1 }, FakeHttpsError
  ).secretHash;
  const db = createDb({
    [`guestRecoveryMappings/${hash}`]: { guestUid: "original-guest", status: "active" }
  });
  const tokenRequests = [];
  const handler = createRecoverGuestAccountHandler({
    db,
    auth: {
      async getUser(uid) {
        assert.equal(uid, "original-guest");
        return { providerData: [] };
      },
      async createCustomToken(uid, claims) {
        tokenRequests.push({ uid, claims });
        return "custom-token";
      }
    },
    requesterHasContent: async () => false,
    serverTimestamp: () => "time",
    HttpsError: FakeHttpsError
  });
  assert.deepEqual(await handler({
    auth: { uid: "temporary-guest", token: anonymousToken },
    data: { recoverySecret: secret, protocolVersion: 1 }
  }), { customToken: "custom-token" });
  assert.deepEqual(tokenRequests, [{ uid: "original-guest", claims: { memoirGuest: true } }]);
  assert.equal(db.rows.get(`guestRecoveryMappings/${hash}`).status, "active");
  assert.equal(db.rows.get(`guestRecoveryMappings/${hash}`).lastRecoveredAt, "time");
});

test("recovery blocks linked targets and either account deletion marker", async () => {
  const hash = normalizedRecoveryRequest(
    { recoverySecret: secret, protocolVersion: 1 }, FakeHttpsError
  ).secretHash;
  const request = {
    auth: { uid: "temporary-guest", token: anonymousToken },
    data: { recoverySecret: secret, protocolVersion: 1 }
  };
  const linkedHandler = createRecoverGuestAccountHandler({
    db: createDb({
      [`guestRecoveryMappings/${hash}`]: { guestUid: "linked", status: "active" }
    }),
    auth: { async getUser() { return { providerData: [{ providerId: "apple.com" }] }; } },
    requesterHasContent: async () => false,
    serverTimestamp: () => "time",
    HttpsError: FakeHttpsError
  });
  await assert.rejects(linkedHandler(request), (error) => error.code === "failed-precondition");

  for (const deletedUid of ["original-guest", "temporary-guest"]) {
    const handler = createRecoverGuestAccountHandler({
      db: createDb({
        [`guestRecoveryMappings/${hash}`]: { guestUid: "original-guest", status: "active" },
        [`accountDeletionRequests/${deletedUid}`]: { status: "complete" }
      }),
      auth: { async getUser() { throw new Error("must not inspect deleted account"); } },
      requesterHasContent: async () => false,
      serverTimestamp: () => "time",
      HttpsError: FakeHttpsError
    });
    await assert.rejects(handler(request), (error) => error.code === "failed-precondition");
  }
});

test("recovery never replaces a different guest account that already has data", async () => {
  const hash = normalizedRecoveryRequest(
    { recoverySecret: secret, protocolVersion: 1 }, FakeHttpsError
  ).secretHash;
  const handler = createRecoverGuestAccountHandler({
    db: createDb({
      [`guestRecoveryMappings/${hash}`]: { guestUid: "original-guest", status: "active" }
    }),
    auth: {
      async getUser() { throw new Error("must not inspect target"); },
      async createCustomToken() { throw new Error("must not create token"); }
    },
    requesterHasContent: async (uid) => {
      assert.equal(uid, "temporary-guest");
      return true;
    },
    serverTimestamp: () => "time",
    HttpsError: FakeHttpsError
  });

  await assert.rejects(handler({
    auth: { uid: "temporary-guest", token: anonymousToken },
    data: { recoverySecret: secret, protocolVersion: 1 }
  }), (error) => error.code === "failed-precondition");
});

test("revocation updates every mapping owned by the authenticated UID", async () => {
  const db = createDb({
    "guestRecoveryMappings/a": { guestUid: "guest-1", status: "active" },
    "guestRecoveryMappings/b": { guestUid: "guest-1", status: "active" },
    "guestRecoveryMappings/c": { guestUid: "guest-2", status: "active" }
  });
  assert.equal(await revokeGuestRecoveryMappings({
    db, guestUid: "guest-1", serverTimestamp: () => "time"
  }), 2);
  assert.equal(db.rows.get("guestRecoveryMappings/a").status, "revoked");
  assert.equal(db.rows.get("guestRecoveryMappings/b").status, "revoked");
  assert.equal(db.rows.get("guestRecoveryMappings/c").status, "active");

  const handler = createRevokeGuestRecoveryHandler({
    db, serverTimestamp: () => "later", HttpsError: FakeHttpsError
  });
  assert.deepEqual(await handler({ auth: { uid: "guest-2", token: {} } }), { status: "revoked" });
  assert.equal(db.rows.get("guestRecoveryMappings/c").status, "revoked");
});
