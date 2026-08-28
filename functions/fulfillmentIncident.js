"use strict";

const crypto = require("crypto");

function fulfillmentIncidentId(stripeSessionId) {
  const normalized = String(stripeSessionId || "").trim();
  if (!normalized) throw new Error("Stripe session id is required");
  return `artifact_${crypto.createHash("sha256").update(normalized).digest("hex").slice(0, 32)}`;
}

function buildArtifactFulfillmentIncident({
  stripeSession,
  checkoutKind,
  userId,
  cartOrderGroupId = null,
  bookVersionIds,
  serverTimestamp
}) {
  if (!stripeSession?.id || !userId || typeof serverTimestamp !== "function") {
    throw new Error("Fulfillment incident dependencies are required");
  }
  const normalizedBookIds = Array.from(new Set((bookVersionIds || [])
    .map((value) => String(value || "").trim())
    .filter(Boolean)));
  if (normalizedBookIds.length === 0) {
    throw new Error("Fulfillment incident requires a book version");
  }
  const incidentId = fulfillmentIncidentId(stripeSession.id);
  const kind = checkoutKind === "cart" ? "cart" : "single_book";
  const subject = kind === "cart"
    ? `Paid cart needs refund review — ${cartOrderGroupId || stripeSession.id}`
    : `Paid book needs refund review — ${stripeSession.id}`;
  const body = `Stripe session ${stripeSession.id} was paid, but its exact PDF generation was unavailable or changed before order creation.\n` +
    `User: ${userId}\nBooks: ${normalizedBookIds.join(", ")}\n\n` +
    "Do not print. Review the durable incident and refund the payment or restore the exact paid artifacts.";
  return {
    incidentId,
    incidentType: "paid_artifact_mismatch",
    status: "open",
    checkoutKind: kind,
    userId,
    cartOrderGroupId,
    stripeSessionId: stripeSession.id,
    stripePaymentIntentId: stripeSession.payment_intent || null,
    amountTotal: stripeSession.amount_total != null ? stripeSession.amount_total : null,
    currency: stripeSession.currency || "usd",
    customerEmail: stripeSession.customer_details?.email || stripeSession.customer_email || null,
    bookVersionIds: normalizedBookIds,
    fulfillmentHold: true,
    alertSubject: subject,
    alertBody: body,
    alertDelivered: false,
    alertAttempts: 0,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp()
  };
}

async function deliverFulfillmentIncidentAlert({
  incidentRef,
  incident,
  sendAlert,
  serverTimestamp,
  increment
}) {
  if (!incidentRef?.set || typeof sendAlert !== "function" ||
      typeof serverTimestamp !== "function" || typeof increment !== "function") {
    throw new Error("Incident alert dependencies are required");
  }
  const delivered = await sendAlert(incident.alertSubject, incident.alertBody);
  const update = {
    alertAttempts: increment(1),
    lastAlertAttemptAt: serverTimestamp(),
    updatedAt: serverTimestamp()
  };
  if (delivered) {
    update.alertDelivered = true;
    update.alertDeliveredAt = serverTimestamp();
  }
  await incidentRef.set(update, { merge: true });
  return delivered;
}

module.exports = {
  buildArtifactFulfillmentIncident,
  deliverFulfillmentIncidentAlert,
  fulfillmentIncidentId
};
