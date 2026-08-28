const assert = require("assert");
const {
  normalizeCheckoutSessionId,
  checkoutSessionBelongsToUser,
  checkoutSessionHasConfirmedPayment,
  createVerifyCheckoutReturnHandler
} = require("./checkoutReturnVerification");

async function expectCode(promise, code) {
  try {
    await promise;
    assert.fail(`Expected ${code}`);
  } catch (error) {
    assert.strictEqual(error.code, code);
  }
}

async function run() {
  const liveId = `cs_live_${"a".repeat(24)}`;
  assert.strictEqual(normalizeCheckoutSessionId(` ${liveId} `), liveId);
  assert.strictEqual(normalizeCheckoutSessionId("cs_live_bad/path"), null);
  assert.strictEqual(normalizeCheckoutSessionId("not-a-session"), null);

  const paid = {
    id: liveId,
    status: "complete",
    payment_status: "paid",
    metadata: { userId: "user-a" }
  };
  assert.strictEqual(checkoutSessionBelongsToUser(paid, "user-a"), true);
  assert.strictEqual(checkoutSessionBelongsToUser(paid, "user-b"), false);
  assert.strictEqual(checkoutSessionHasConfirmedPayment(paid), true);
  assert.strictEqual(checkoutSessionHasConfirmedPayment({ ...paid, payment_status: "unpaid" }), false);

  const handler = createVerifyCheckoutReturnHandler({
    createStripeClient: () => ({ checkout: { sessions: { retrieve: async () => paid } } }),
    orderRecordExists: async () => true
  });
  const response = await handler({ auth: { uid: "user-a" }, data: { sessionId: liveId } });
  assert.deepStrictEqual(response, {
    verified: true,
    paymentConfirmed: true,
    orderRecorded: true,
    sessionId: liveId,
    checkoutStatus: "complete",
    paymentStatus: "paid"
  });

  const awaitingWebhookHandler = createVerifyCheckoutReturnHandler({
    createStripeClient: () => ({ checkout: { sessions: { retrieve: async () => paid } } }),
    orderRecordExists: async () => false
  });
  const awaitingWebhook = await awaitingWebhookHandler({
    auth: { uid: "user-a" }, data: { sessionId: liveId }
  });
  assert.strictEqual(awaitingWebhook.verified, false);
  assert.strictEqual(awaitingWebhook.paymentConfirmed, true);
  assert.strictEqual(awaitingWebhook.orderRecorded, false);

  await expectCode(handler({ auth: null, data: { sessionId: liveId } }), "unauthenticated");
  await expectCode(handler({ auth: { uid: "user-b" }, data: { sessionId: liveId } }), "permission-denied");

  const missingHandler = createVerifyCheckoutReturnHandler({
    createStripeClient: () => ({ checkout: { sessions: { retrieve: async () => {
      const error = new Error("missing");
      error.code = "resource_missing";
      throw error;
    } } } }),
    orderRecordExists: async () => false
  });
  await expectCode(missingHandler({ auth: { uid: "user-a" }, data: { sessionId: liveId } }), "not-found");
}

run()
  .then(() => console.log("checkout return verification tests passed"))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
