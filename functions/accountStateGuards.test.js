const assert = require("assert");
const {
  assertAccountAvailableForCheckout,
  assertAccountNotDeleting
} = require("./accountStateGuards");

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function dbWithMarker(exists) {
  return {
    collection(name) {
      assert.strictEqual(name, "accountDeletionRequests");
      return {
        doc(userId) {
          assert.strictEqual(userId, "user-1");
          return { async get() { return { exists }; } };
        }
      };
    }
  };
}

async function run() {
  await assertAccountAvailableForCheckout(dbWithMarker(false), "user-1", FakeHttpsError);
  await assert.rejects(
    assertAccountAvailableForCheckout(dbWithMarker(true), "user-1", FakeHttpsError),
    (error) => error.code === "failed-precondition"
  );
  await assertAccountNotDeleting(dbWithMarker(false), "user-1");
  await assert.rejects(
    assertAccountNotDeleting(dbWithMarker(true), "user-1"),
    (error) => error.accountDeletionRequested === true && error.permanent === true
  );
  console.log("accountStateGuards.test.js: all assertions passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
