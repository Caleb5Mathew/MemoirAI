"use strict";

const assert = require("assert");
const {
  appendLuluStatusHistory,
  buildPaidArtifactSnapshot,
  buildSingleBookOrderRecords,
  chooseMonotonicOrderStatus,
  claimOrderForFulfillment,
  commitSingleBookOrderOnce,
  stripeSessionOrderId,
  missingCartSessionDisposition
} = require("./orderFlowIdempotency");

function createMemoryTransactions(initial = {}) {
  const docs = new Map(Object.entries(initial));
  let queue = Promise.resolve();
  const runTransaction = (callback) => {
    const result = queue.then(async () => {
      const transaction = {
        async get(ref) {
          return {
            exists: docs.has(ref),
            data: () => docs.get(ref)
          };
        },
        set(ref, value, options) {
          const next = options?.merge ? { ...(docs.get(ref) || {}), ...value } : value;
          docs.set(ref, next);
        },
        update(ref, value) {
          docs.set(ref, { ...(docs.get(ref) || {}), ...value });
        }
      };
      return callback(transaction);
    });
    queue = result.then(() => undefined, () => undefined);
    return result;
  };
  return { docs, runTransaction };
}

async function run() {
  const sessionId = "cs_live_duplicate_webhook";
  const orderId = stripeSessionOrderId(sessionId);
  assert.strictEqual(orderId, stripeSessionOrderId(sessionId));

  const stripeStore = createMemoryTransactions();
  const commit = () => commitSingleBookOrderOnce({
    runTransaction: stripeStore.runTransaction,
    orderRef: "order",
    paidCheckoutRef: "paid",
    bookVersionRef: "book",
    orderData: { orderId, stripeSessionId: sessionId },
    paidCheckoutData: { orderIds: [orderId] },
    bookVersionData: { hasPaidOrder: true }
  });
  const duplicateResults = await Promise.all([commit(), commit()]);
  assert.strictEqual(duplicateResults.filter((result) => result.created).length, 1);
  assert.strictEqual(stripeStore.docs.get("order").stripeSessionId, sessionId);

  const records = buildSingleBookOrderRecords({
    session: {
      id: sessionId,
      payment_intent: "pi_1",
      amount_total: 4299,
      currency: "usd",
      customer_details: { email: "buyer@example.com" },
      metadata: {
        userId: "user-1",
        bookVersionId: "book-1",
        totalCents: "4299",
        shippingLevel: "MAIL",
        coverStoragePath: "users/user-1/bookVersions/book-1/cover.pdf",
        pdfStoragePath: "users/user-1/bookVersions/book-1/interior.pdf"
      }
    },
    bookVersion: {
      profileId: "profile-1",
      printTitle: "A Life Story",
      coverURL: "https://example.com/cover.pdf",
      pdfURL: "https://example.com/interior.pdf",
      coverArtifactGeneration: "17",
      coverArtifactSize: 1024,
      pdfArtifactGeneration: "18",
      pdfArtifactSize: 2048,
      pageCount: 48
    },
    expectedFulfillmentItem: {
      selectedPodPackageId: "0850X1100FCSTDPB080CW444MXX",
      fulfillmentFingerprint: "paid-fingerprint",
      printTitle: "Paid Title"
    },
    shippingAddress: { name: "Buyer" },
    isStripeTestMode: false,
    serverTimestamp: () => "SERVER_TIME"
  });
  assert.strictEqual(records.orderData.orderId, orderId);
  assert.strictEqual(records.orderData.status, "paid");
  assert.strictEqual(records.paidCheckoutData.items.length, 1);
  assert.strictEqual(records.orderData.coverArtifactGeneration, "17");
  assert.strictEqual(records.orderData.interiorArtifactGeneration, "18");
  assert.strictEqual(records.paidCheckoutData.items[0].pdfArtifactSize, 2048);
  assert.strictEqual(records.orderData.pageCount, 48);
  assert.strictEqual(records.orderData.printTitle, "Paid Title");
  assert.strictEqual(records.orderData.selectedPodPackageId, "0850X1100FCSTDPB080CW444MXX");
  assert.strictEqual(records.orderData.fulfillmentFingerprint, "paid-fingerprint");
  assert.strictEqual(records.bookVersionData.lastPaidStripeSessionId, sessionId);

  const immutableSnapshot = buildPaidArtifactSnapshot({
    bookVersion: {
      pageCount: 48,
      printTitle: "Mutable live title",
      coverArtifactGeneration: "17",
      pdfArtifactGeneration: "18"
    },
    checkoutItem: {
      selectedPodPackageId: "paid-pod",
      printTitle: "Paid Title",
      fulfillmentFingerprint: "paid-fingerprint"
    }
  });
  assert.deepStrictEqual(immutableSnapshot, {
    pageCount: 48,
    selectedPodPackageId: "paid-pod",
    printTitle: "Paid Title",
    fulfillmentFingerprint: "paid-fingerprint",
    coverArtifactGeneration: "17",
    coverArtifactSize: 0,
    interiorArtifactGeneration: "18",
    interiorArtifactSize: 0
  });
  assert.deepStrictEqual(missingCartSessionDisposition({
    attemptStripeSessionId: "cs_recovered",
    existingOrderCount: 0
  }), { action: "recover_session", sessionId: "cs_recovered" });
  assert.deepStrictEqual(missingCartSessionDisposition({
    attemptStripeSessionId: "",
    existingOrderCount: 1
  }), { action: "mark_paid" });
  assert.deepStrictEqual(missingCartSessionDisposition({
    attemptStripeSessionId: null,
    existingOrderCount: 0
  }), { action: "mark_abandoned" });

  const fulfillmentStore = createMemoryTransactions({ order: { status: "paid" } });
  const claim = (token) => claimOrderForFulfillment({
    runTransaction: fulfillmentStore.runTransaction,
    orderRef: "order",
    source: "test",
    nowMillis: 1_000,
    leaseToken: token,
    timestampFromMillis: (value) => value,
    serverTimestamp: () => 1_000
  });
  const claims = await Promise.all([claim("lease-a"), claim("lease-b")]);
  assert.strictEqual(claims.filter((result) => result.acquired).length, 1);
  assert.strictEqual(claims.find((result) => !result.acquired).reason, "lease_active");

  assert.strictEqual(chooseMonotonicOrderStatus("delivered", "printing"), "delivered");
  assert.strictEqual(chooseMonotonicOrderStatus("shipped", "submitted_to_printer"), "shipped");
  assert.strictEqual(chooseMonotonicOrderStatus("printing", "shipped"), "shipped");

  let history = [];
  history = appendLuluStatusHistory(history, { status: "DELIVERED", source: "lulu_webhook", timestamp: "one" }, 2);
  history = appendLuluStatusHistory(history, { status: "DELIVERED", source: "lulu_webhook", timestamp: "two" }, 2);
  assert.strictEqual(history.length, 1);
  history = appendLuluStatusHistory(history, { status: "SHIPPED", source: "lulu_sync", timestamp: "three" }, 2);
  history = appendLuluStatusHistory(history, { status: "IN_PRODUCTION", source: "lulu_sync", timestamp: "four" }, 2);
  assert.deepStrictEqual(history.map((entry) => entry.status), ["SHIPPED", "IN_PRODUCTION"]);

  console.log("orderFlowIdempotency.test.js: all assertions passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
