"use strict";

const assert = require("assert");
const {
  canonicalSharedAudioFile,
  firebaseDownloadURL,
  createRevokeSharedMemoryAccessHandler
} = require("./sharedAccessRevocation");

const memoryId = "11111111-1111-4111-8111-111111111111";
assert.strictEqual(
  canonicalSharedAudioFile("owner", memoryId, `users/owner/audio/${memoryId}.m4a`),
  `${memoryId}.m4a`
);
assert.strictEqual(
  canonicalSharedAudioFile("owner", memoryId, `users/other/audio/${memoryId}.m4a`),
  null
);
assert.strictEqual(canonicalSharedAudioFile("owner", "bad", "users/owner/audio/bad.m4a"), null);
assert.strictEqual(
  firebaseDownloadURL("memoir.appspot.com", "users/owner/audio/a file.m4a", "token/value"),
  "https://firebasestorage.googleapis.com/v0/b/memoir.appspot.com/o/users%2Fowner%2Faudio%2Fa%20file.m4a?alt=media&token=token%2Fvalue"
);

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function reference(path, rows) {
  return {
    path,
    async get() {
      const value = rows.get(path);
      return { exists: value != null, data: () => value };
    },
    collection(name) { return { doc(id) { return reference(`${path}/${name}/${id}`, rows); } }; }
  };
}

async function run() {
  const rows = new Map([
    [`users/owner/accessGrants/${memoryId}__requester`, {
      memoryId,
      requesterUid: "requester",
      revoked: false
    }],
    [`users/owner/memories/${memoryId}`, {
      audioStoragePath: `users/owner/audio/${memoryId}.m4a`
    }]
  ]);
  const metadataWrites = [];
  const pendingBatchOperations = [];
  const db = {
    collection(name) { return { doc(id) { return reference(`${name}/${id}`, rows); } }; },
    batch() {
      return {
        delete(ref) { pendingBatchOperations.push(() => rows.delete(ref.path)); },
        set(ref, value, options) {
          pendingBatchOperations.push(() => {
            rows.set(ref.path, options?.merge ? { ...(rows.get(ref.path) || {}), ...value } : value);
          });
        },
        async commit() { pendingBatchOperations.splice(0).forEach((operation) => operation()); }
      };
    }
  };
  const handler = createRevokeSharedMemoryAccessHandler({
    db,
    bucket: {
      name: "memoir.appspot.com",
      file(path) {
        assert.strictEqual(path, `users/owner/audio/${memoryId}.m4a`);
        return {
          exists: async () => [true],
          getMetadata: async () => [{ metadata: { existing: "kept" } }],
          setMetadata: async (value) => metadataWrites.push(value)
        };
      }
    },
    HttpsError: FakeHttpsError,
    serverTimestamp: () => "SERVER_TIME",
    randomUUID: () => "replacement-token"
  });
  assert.deepStrictEqual(await handler({
    auth: { uid: "owner" },
    data: { grantId: `${memoryId}__requester`, memoryId }
  }), { status: "revoked" });
  assert.strictEqual(rows.has(`users/owner/accessGrants/${memoryId}__requester`), false);
  assert.strictEqual(rows.has(`users/owner/sharedAudioAccess/${memoryId}.m4a__requester`), false);
  assert.strictEqual(rows.get(`users/owner/accessRequests/${memoryId}__requester`).status, "denied");
  assert.strictEqual(metadataWrites[0].metadata.existing, "kept");
  assert.ok(metadataWrites[0].metadata.firebaseStorageDownloadTokens);
  assert.strictEqual(
    rows.get(`users/owner/memories/${memoryId}`).audioURL,
    `https://firebasestorage.googleapis.com/v0/b/memoir.appspot.com/o/users%2Fowner%2Faudio%2F${memoryId}.m4a?alt=media&token=replacement-token`
  );

  const legacyRows = new Map([
    ["users/owner/accessGrants/requester", { requesterUid: "requester", revoked: false }],
    ["users/owner/accessRequests/requester", {
      requesterUid: "requester",
      memoryId,
      status: "approved"
    }],
    [`users/owner/memories/${memoryId}`, {}]
  ]);
  const legacyBatchOperations = [];
  const legacyHandler = createRevokeSharedMemoryAccessHandler({
    db: {
      collection(name) {
        return { doc(id) { return reference(`${name}/${id}`, legacyRows); } };
      },
      batch() {
        return {
          delete(ref) { legacyBatchOperations.push(() => legacyRows.delete(ref.path)); },
          set(ref, value, options) {
            legacyBatchOperations.push(() => legacyRows.set(
              ref.path,
              options?.merge ? { ...(legacyRows.get(ref.path) || {}), ...value } : value
            ));
          },
          async commit() {
            legacyBatchOperations.splice(0).forEach((operation) => operation());
          }
        };
      }
    },
    bucket: { name: "memoir.appspot.com", file() { throw new Error("unexpected audio file"); } },
    HttpsError: FakeHttpsError,
    serverTimestamp: () => "SERVER_TIME"
  });
  assert.deepStrictEqual(await legacyHandler({
    auth: { uid: "owner" },
    data: { grantId: "requester", memoryId }
  }), { status: "revoked" });
  assert.strictEqual(legacyRows.has("users/owner/accessGrants/requester"), false);
  assert.strictEqual(legacyRows.get("users/owner/accessRequests/requester").status, "denied");
  await assert.rejects(
    () => handler({ auth: null, data: {} }),
    (error) => error.code === "unauthenticated"
  );
  console.log("sharedAccessRevocation.test.js: all assertions passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
