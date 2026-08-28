const assert = require("assert");
const {
  assertRecentAuthentication,
  blockingPendingCheckoutIds,
  createDeleteOwnAccountHandler,
  deleteMemoryIndexes,
  deleteUnretainedStorage,
  findBlockingPendingCheckouts,
  retainedOrderArtifactPaths
} = require("./accountDeletion");

async function run() {
  const pendingDoc = (id, status) => ({ id, data: () => ({ status }) });
  assert.deepStrictEqual(blockingPendingCheckoutIds([
    pendingDoc("open", "pending_stripe"),
    pendingDoc("paid", "paid"),
    pendingDoc("expired", "checkout_expired"),
    pendingDoc("unknown", "")
  ]), ["open", "unknown"]);

  const checkoutDb = {
    collection(name) {
      if (name === "users") {
        return {
          doc() {
            return {
              collection(collectionName) {
                assert.strictEqual(collectionName, "pendingCartCheckouts");
                return { async get() { return { docs: [pendingDoc("cart", "pending_stripe")] }; } };
              }
            };
          }
        };
      }
      assert.strictEqual(name, "pendingSingleCheckouts");
      return {
        where(field, op, value) {
          assert.deepStrictEqual([field, op, value], ["userId", "==", "user-1"]);
          return { async get() { return { docs: [pendingDoc("single", "paid")] }; } };
        }
      };
    }
  };
  assert.deepStrictEqual(
    await findBlockingPendingCheckouts(checkoutDb, "user-1"),
    ["cart"]
  );

  const deletedIndexes = [];
  const indexOwners = { victimMemory: "victim", collisionMemory: "other-user" };
  const memoriesRef = {
    parent: { id: "victim" },
    async *stream() {
      yield { id: "victimMemory" };
      yield { id: "collisionMemory" };
    }
  };
  const indexDb = {
    collection(name) {
      assert.strictEqual(name, "memoryIndex");
      return {
        doc(id) {
          return {
            path: `memoryIndex/${id}`,
            async get() {
              return { exists: true, data: () => ({ ownerId: indexOwners[id] }) };
            }
          };
        }
      };
    },
    batch() {
      return {
        delete(ref) { deletedIndexes.push(ref.path); },
        async commit() {}
      };
    }
  };
  await deleteMemoryIndexes(indexDb, memoriesRef);
  assert.deepStrictEqual(deletedIndexes, ["memoryIndex/victimMemory"]);

  const retained = retainedOrderArtifactPaths([
    {
      coverPdfStoragePath: "users/user-1/bookVersions/book-1/cover.pdf",
      interiorPdfStoragePath: "users/user-1/bookVersions/book-1/book.pdf"
    },
    { interiorPdfStoragePath: "users/other/bookVersions/stolen/book.pdf" },
    { interiorPdfStoragePath: "users/user-1/audio/not-a-book.m4a" }
  ], "user-1");
  assert.deepStrictEqual([...retained].sort(), [
    "users/user-1/bookVersions/book-1/book.pdf",
    "users/user-1/bookVersions/book-1/cover.pdf"
  ]);

  const deleted = [];
  const files = [
    "users/user-1/audio/a.m4a",
    "users/user-1/bookVersions/book-1/book.pdf",
    "users/user-1/bookVersions/book-1/pages/page_001.png"
  ].map((name) => ({ name, async delete() { deleted.push(name); } }));
  await deleteUnretainedStorage(
    { async getFiles() { return [files]; } },
    "user-1",
    new Set(["users/user-1/bookVersions/book-1/book.pdf"])
  );
  assert.deepStrictEqual(deleted.sort(), [
    "users/user-1/audio/a.m4a",
    "users/user-1/bookVersions/book-1/pages/page_001.png"
  ]);

  class FakeHttpsError extends Error {
    constructor(code, message, details) {
      super(message);
      this.code = code;
      this.details = details;
    }
  }
  const unauthenticated = createDeleteOwnAccountHandler({
    db: {}, bucket: {}, auth: {}, serverTimestamp: () => "time", HttpsError: FakeHttpsError
  });
  await assert.rejects(
    unauthenticated({ auth: null }),
    (error) => error.code === "unauthenticated"
  );

  assertRecentAuthentication({
    auth: { token: { auth_time: 1_000, firebase: { sign_in_provider: "password" } } }
  }, () => 1_300, FakeHttpsError);
  assertRecentAuthentication({
    auth: { token: { firebase: { sign_in_provider: "anonymous" } } }
  }, () => 50_000, FakeHttpsError);
  assert.throws(
    () => assertRecentAuthentication({
      auth: { token: { auth_time: 1_000, firebase: { sign_in_provider: "google.com" } } }
    }, () => 1_301, FakeHttpsError),
    (error) => error.code === "failed-precondition"
      && error.details.reason === "requires-recent-login"
  );
  assert.throws(
    () => assertRecentAuthentication({
      auth: {
        token: {
          auth_time: 1,
          firebase: {
            sign_in_provider: "anonymous",
            identities: { "google.com": ["google-user"] }
          }
        }
      }
    }, () => 10_000, FakeHttpsError),
    (error) => error.code === "failed-precondition"
  );
  assert.throws(
    () => assertRecentAuthentication({ auth: { token: {} } }, () => 1_000, FakeHttpsError),
    (error) => error.code === "failed-precondition"
  );

  const writes = [];
  let destructiveCallCount = 0;
  const completed = createDeleteOwnAccountHandler({
    db: {
      collection(name) {
        assert.strictEqual(name, "accountDeletionRequests");
        return {
          doc(userId) {
            assert.strictEqual(userId, "deleted-user");
            return {
              async get() {
                return {
                  exists: true,
                  data: () => ({ status: "complete", retainedOrderCount: 2 })
                };
              },
              async set(value) { writes.push(value); }
            };
          }
        };
      },
      recursiveDelete() { destructiveCallCount += 1; }
    },
    bucket: { getFiles() { destructiveCallCount += 1; } },
    auth: { deleteUser() { destructiveCallCount += 1; } },
    serverTimestamp: () => "time",
    HttpsError: FakeHttpsError,
    nowSeconds: () => 10_000
  });
  assert.deepStrictEqual(await completed({
    auth: { uid: "deleted-user", token: { auth_time: 1 } }
  }), { status: "complete", retainedOrderRecords: 2 });
  assert.deepStrictEqual(writes, []);
  assert.strictEqual(destructiveCallCount, 0);

  const resumedWrites = [];
  let resumedAuthDeletes = 0;
  const resumeAuthDeletion = createDeleteOwnAccountHandler({
    db: {
      collection(name) {
        assert.strictEqual(name, "accountDeletionRequests");
        return {
          doc() {
            return {
              async get() {
                return {
                  exists: true,
                  data: () => ({ status: "deleting_auth", retainedOrderCount: 3 })
                };
              },
              async set(value) { resumedWrites.push(value); }
            };
          }
        };
      }
    },
    bucket: {},
    auth: { async deleteUser() { resumedAuthDeletes += 1; } },
    serverTimestamp: () => "time",
    HttpsError: FakeHttpsError,
    nowSeconds: () => 10_000
  });
  assert.deepStrictEqual(await resumeAuthDeletion({
    auth: { uid: "deleted-user", token: { auth_time: 1 } }
  }), { status: "complete", retainedOrderRecords: 3 });
  assert.strictEqual(resumedAuthDeletes, 1);
  assert.strictEqual(resumedWrites[0].status, "complete");

  console.log("accountDeletion.test.js: all assertions passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
