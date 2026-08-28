"use strict";

const assert = require("assert");
const {
  buildArtifactFulfillmentIncident,
  deliverFulfillmentIncidentAlert,
  fulfillmentIncidentId
} = require("./fulfillmentIncident");

async function run() {
  const session = {
    id: "cs_live_paid_artifact",
    payment_intent: "pi_1",
    amount_total: 4299,
    currency: "usd",
    customer_details: { email: "buyer@example.com" }
  };

  const firstId = fulfillmentIncidentId(session.id);
  assert.strictEqual(firstId, fulfillmentIncidentId(session.id));
  assert.notStrictEqual(firstId, fulfillmentIncidentId("cs_live_other"));

  const incident = buildArtifactFulfillmentIncident({
    stripeSession: session,
    checkoutKind: "cart",
    userId: "user-1",
    cartOrderGroupId: "cart-1",
    bookVersionIds: ["book-1", "book-1", "book-2", ""],
    serverTimestamp: () => "SERVER_TIME"
  });
  assert.strictEqual(incident.incidentId, firstId);
  assert.strictEqual(incident.alertDelivered, false);
  assert.strictEqual(incident.fulfillmentHold, true);
  assert.deepStrictEqual(incident.bookVersionIds, ["book-1", "book-2"]);
  assert.match(incident.alertBody, /Do not print/);

  const writes = [];
  const delivered = await deliverFulfillmentIncidentAlert({
    incidentRef: { set: async (value, options) => writes.push({ value, options }) },
    incident,
    sendAlert: async (subject, body) => subject === incident.alertSubject && body === incident.alertBody,
    serverTimestamp: () => "SERVER_TIME",
    increment: (value) => ({ increment: value })
  });
  assert.strictEqual(delivered, true);
  assert.strictEqual(writes[0].value.alertDelivered, true);
  assert.deepStrictEqual(writes[0].value.alertAttempts, { increment: 1 });

  assert.throws(
    () => buildArtifactFulfillmentIncident({
      stripeSession: session,
      checkoutKind: "single_book",
      userId: "user-1",
      bookVersionIds: [],
      serverTimestamp: () => "SERVER_TIME"
    }),
    /requires a book version/
  );

  console.log("fulfillmentIncident.test.js: all assertions passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
