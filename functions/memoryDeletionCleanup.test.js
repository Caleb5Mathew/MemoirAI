const assert = require("assert");
const { createMemoryDeletionCleanupHandler } = require("./memoryDeletionCleanup");

function makeDependencies({
  commitError = null,
  storageErrors = {},
  memoryIndexOwner = "user-1"
} = {}) {
  const batchOperations = [];
  const reference = (path) => ({
    path,
    collection(name) { return reference(`${path}/${name}`); },
    doc(id) { return reference(`${path}/${id}`); },
    async get() {
      if (path === "memoryIndex/memory-1" && memoryIndexOwner) {
        return { exists: true, data: () => ({ ownerId: memoryIndexOwner }) };
      }
      return { exists: false, data: () => ({}) };
    }
  });
  const db = {
    collection(name) { return reference(name); },
    batch() {
      return {
        set(ref, data) { batchOperations.push(["set", ref.path, data]); },
        delete(ref) { batchOperations.push(["delete", ref.path]); },
        async commit() {
          if (commitError) throw commitError;
        }
      };
    }
  };
  const deletedPaths = [];
  const bucket = {
    file(path) {
      return {
        async delete() {
          deletedPaths.push(path);
          const extension = path.endsWith(".m4a") ? "m4a" : "caf";
          if (storageErrors[extension]) throw storageErrors[extension];
        }
      };
    }
  };
  return { db, bucket, batchOperations, deletedPaths };
}

async function run() {
  const event = { params: { userId: "user-1", memoryId: "memory-1" } };

  const success = makeDependencies({ storageErrors: { caf: { code: 404 } } });
  await createMemoryDeletionCleanupHandler({
    db: success.db,
    bucket: success.bucket,
    serverTimestamp: () => "server-time"
  })(event);
  assert.strictEqual(success.batchOperations.filter(([kind]) => kind === "set").length, 3);
  assert.strictEqual(success.batchOperations.filter(([kind]) => kind === "delete").length, 2);
  assert.deepStrictEqual(success.deletedPaths, [
    "users/user-1/audio/memory-1.m4a",
    "users/user-1/audio/memory-1.caf"
  ]);

  const collision = makeDependencies({ memoryIndexOwner: "victim" });
  await createMemoryDeletionCleanupHandler({
    db: collision.db,
    bucket: collision.bucket,
    serverTimestamp: () => "server-time"
  })(event);
  assert.deepStrictEqual(
    collision.batchOperations.filter(([kind, path]) => kind === "delete" && path.startsWith("memoryIndex/")),
    [],
    "deleting an attacker collision must preserve the victim's QR index"
  );

  const commitFailure = new Error("transient Firestore failure");
  const failedCommit = makeDependencies({ commitError: commitFailure });
  await assert.rejects(
    createMemoryDeletionCleanupHandler({
      db: failedCommit.db,
      bucket: failedCommit.bucket,
      serverTimestamp: () => "server-time"
    })(event),
    commitFailure
  );

  const storageFailure = new Error("transient Storage failure");
  storageFailure.code = 503;
  const failedStorage = makeDependencies({ storageErrors: { m4a: storageFailure } });
  await assert.rejects(
    createMemoryDeletionCleanupHandler({
      db: failedStorage.db,
      bucket: failedStorage.bucket,
      serverTimestamp: () => "server-time"
    })(event),
    storageFailure
  );

  console.log("memoryDeletionCleanup.test.js: all assertions passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
