"use strict";

const crypto = require("crypto");

const FULFILLMENT_LEASE_MILLIS = 10 * 60 * 1000;
const LULU_STATUS_HISTORY_LIMIT = 50;

function stripeSessionOrderId(sessionId) {
  const normalized = String(sessionId || "").trim();
  if (!normalized) {
    throw new Error("Missing Stripe session id");
  }
  const digest = crypto.createHash("sha256").update(normalized).digest("hex").slice(0, 32);
  return `ord_stripe_${digest}`;
}

function buildPaidArtifactSnapshot({ bookVersion, checkoutItem }) {
  const record = bookVersion && typeof bookVersion === "object" ? bookVersion : {};
  const item = checkoutItem && typeof checkoutItem === "object" ? checkoutItem : {};
  const pageCount = Number(record.pageCount || record.pages?.length || 0);
  const selectedPodPackageId = String(item.selectedPodPackageId || "").trim();
  if (!Number.isSafeInteger(pageCount) || pageCount <= 0 || !selectedPodPackageId) {
    throw new Error("Paid fulfillment snapshot is incomplete");
  }
  return {
    pageCount,
    selectedPodPackageId,
    printTitle: item.printTitle || record.printTitle || null,
    fulfillmentFingerprint: String(item.fulfillmentFingerprint || ""),
    coverArtifactGeneration: String(record.coverArtifactGeneration || ""),
    coverArtifactSize: Number(record.coverArtifactSize || 0),
    interiorArtifactGeneration: String(record.pdfArtifactGeneration || ""),
    interiorArtifactSize: Number(record.pdfArtifactSize || 0)
  };
}

function buildSingleBookOrderRecords({
  session,
  bookVersion,
  expectedFulfillmentItem,
  shippingAddress,
  isStripeTestMode,
  serverTimestamp
}) {
  if (!session?.id || typeof serverTimestamp !== "function") {
    throw new Error("Single-book checkout record dependencies are required");
  }
  const meta = session.metadata || {};
  const userId = String(meta.userId || "");
  const bookVersionId = String(meta.bookVersionId || "");
  if (!userId || !bookVersionId) throw new Error("Missing single-book checkout ownership");
  const orderId = stripeSessionOrderId(session.id);
  const lineTotalCents = parseInt(meta.totalCents || "2999", 10);
  if (!Number.isSafeInteger(lineTotalCents) || lineTotalCents <= 0) {
    throw new Error("Invalid single-book checkout total");
  }
  const artifactSnapshot = buildPaidArtifactSnapshot({
    bookVersion,
    checkoutItem: {
      ...(expectedFulfillmentItem || {}),
      selectedPodPackageId: meta.selectedPodPackageId || expectedFulfillmentItem?.selectedPodPackageId,
      printTitle: expectedFulfillmentItem?.printTitle || bookVersion.printTitle || null
    }
  });
  const printTitle = artifactSnapshot.printTitle;
  const profileId = bookVersion.profileId != null ? String(bookVersion.profileId) : null;
  const customerEmail = session.customer_details?.email || session.customer_email || null;
  const item = {
    bookVersionId,
    profileId,
    printTitle,
    productOptionId: meta.selectedProductOptionId || null,
    selectedPodPackageId: artifactSnapshot.selectedPodPackageId,
    pageCount: artifactSnapshot.pageCount,
    fulfillmentFingerprint: artifactSnapshot.fulfillmentFingerprint,
    quantity: 1,
    unitCents: lineTotalCents,
    lineTotalCents,
    coverStoragePath: meta.coverStoragePath,
    pdfStoragePath: meta.pdfStoragePath,
    coverArtifactGeneration: artifactSnapshot.coverArtifactGeneration,
    coverArtifactSize: artifactSnapshot.coverArtifactSize,
    pdfArtifactGeneration: artifactSnapshot.interiorArtifactGeneration,
    pdfArtifactSize: artifactSnapshot.interiorArtifactSize,
    coverURL: bookVersion.coverURL || null,
    pdfURL: bookVersion.pdfURL || null,
    bookDisplayName: bookVersion.bookDisplayName || null,
    userHandle: bookVersion.userHandle || null
  };
  const orderData = {
    orderId,
    bookVersionId,
    userId,
    stripeSessionId: session.id,
    stripePaymentIntentId: session.payment_intent || null,
    luluPrintJobId: null,
    status: "paid",
    luluError: null,
    isTestOrder: Boolean(isStripeTestMode),
    customerEmail,
    shippingAddress,
    shippingLevel: meta.shippingLevel || "MAIL",
    selectedProductOptionId: meta.selectedProductOptionId || null,
    selectedPodPackageId: artifactSnapshot.selectedPodPackageId,
    pageCount: artifactSnapshot.pageCount,
    fulfillmentFingerprint: artifactSnapshot.fulfillmentFingerprint,
    quantity: 1,
    unitCents: lineTotalCents,
    lineTotalCents,
    pricing: { totalCents: lineTotalCents, currency: "usd" },
    printTitle,
    productTitle: null,
    bookDisplayName: bookVersion.bookDisplayName || null,
    userHandle: bookVersion.userHandle || null,
    coverPdfStoragePath: meta.coverStoragePath,
    interiorPdfStoragePath: meta.pdfStoragePath,
    coverArtifactGeneration: artifactSnapshot.coverArtifactGeneration,
    coverArtifactSize: artifactSnapshot.coverArtifactSize,
    interiorArtifactGeneration: artifactSnapshot.interiorArtifactGeneration,
    interiorArtifactSize: artifactSnapshot.interiorArtifactSize,
    coverURL: bookVersion.coverURL || null,
    pdfURL: bookVersion.pdfURL || null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    luluTrackingUrl: null,
    luluStatusHistory: []
  };
  const paidCheckoutData = {
    userId,
    checkoutKind: "single_book",
    cartOrderGroupId: null,
    stripeSessionId: session.id,
    stripePaymentIntentId: session.payment_intent || null,
    currency: session.currency || "usd",
    amountTotal: session.amount_total != null ? session.amount_total : lineTotalCents,
    isTestOrder: Boolean(isStripeTestMode),
    quoteId: null,
    idempotencyKey: null,
    checkoutPath: "single_book",
    items: [item],
    shippingAddress,
    shippingLevel: meta.shippingLevel || "MAIL",
    booksSubtotalCents: lineTotalCents,
    orderShippingCents: 0,
    totalCents: lineTotalCents,
    customerEmail,
    orderIds: [orderId],
    paidAt: serverTimestamp()
  };
  return {
    orderId,
    lineTotalCents,
    orderData,
    paidCheckoutData,
    bookVersionData: {
      hasPaidOrder: true,
      paidAt: serverTimestamp(),
      lastPaidStripeSessionId: session.id,
      pdfStoragePath: meta.pdfStoragePath,
      coverStoragePath: meta.coverStoragePath,
      pdfURL: bookVersion.pdfURL || null,
      coverURL: bookVersion.coverURL || null
    }
  };
}

async function commitSingleBookOrderOnce({
  runTransaction,
  orderRef,
  paidCheckoutRef,
  bookVersionRef,
  orderData,
  paidCheckoutData,
  bookVersionData
}) {
  if (typeof runTransaction !== "function") {
    throw new Error("runTransaction is required");
  }
  return runTransaction(async (transaction) => {
    const existing = await transaction.get(orderRef);
    if (existing.exists) {
      return { created: false, orderId: orderData.orderId };
    }
    transaction.set(orderRef, orderData);
    transaction.set(paidCheckoutRef, paidCheckoutData);
    transaction.set(bookVersionRef, bookVersionData, { merge: true });
    return { created: true, orderId: orderData.orderId };
  });
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  if (value._seconds != null) return Number(value._seconds) * 1000;
  return 0;
}

function fulfillmentClaimDecision(order, nowMillis) {
  const data = order && typeof order === "object" ? order : {};
  if (data.isTestOrder) return { canClaim: false, reason: "test_order" };
  if (data.fulfillmentHold) return { canClaim: false, reason: "fulfillment_hold" };
  if (data.luluPrintJobId) return { canClaim: false, reason: "already_submitted" };

  const status = String(data.status || "");
  const retriable = status === "paid" || status === "lulu_failed" || status === "pending_fulfillment";
  if (!retriable) return { canClaim: false, reason: `status_${status || "missing"}` };

  const leaseExpiresAtMillis = timestampMillis(data.fulfillmentLeaseExpiresAt);
  if (data.fulfillmentLeaseToken && leaseExpiresAtMillis > nowMillis) {
    return { canClaim: false, reason: "lease_active", leaseExpiresAtMillis };
  }
  return { canClaim: true, reason: "claimable" };
}

async function claimOrderForFulfillment({
  runTransaction,
  orderRef,
  source,
  nowMillis = Date.now(),
  leaseMillis = FULFILLMENT_LEASE_MILLIS,
  leaseToken = crypto.randomBytes(16).toString("hex"),
  timestampFromMillis,
  serverTimestamp
}) {
  if (typeof runTransaction !== "function" || typeof timestampFromMillis !== "function" ||
      typeof serverTimestamp !== "function") {
    throw new Error("Fulfillment claim dependencies are required");
  }
  return runTransaction(async (transaction) => {
    const snapshot = await transaction.get(orderRef);
    if (!snapshot.exists) return { acquired: false, reason: "missing_order" };

    const order = snapshot.data() || {};
    const decision = fulfillmentClaimDecision(order, nowMillis);
    if (!decision.canClaim) {
      return { acquired: false, ...decision, order };
    }

    const attempt = Math.max(0, Number(order.fulfillmentAttempt) || 0) + 1;
    const leaseExpiresAt = timestampFromMillis(nowMillis + leaseMillis);
    transaction.update(orderRef, {
      status: "pending_fulfillment",
      fulfillmentLeaseToken: leaseToken,
      fulfillmentLeaseSource: source || "unknown",
      fulfillmentLeaseClaimedAt: serverTimestamp(),
      fulfillmentLeaseExpiresAt: leaseExpiresAt,
      fulfillmentAttempt: attempt,
      updatedAt: serverTimestamp()
    });
    return {
      acquired: true,
      leaseToken,
      leaseExpiresAt,
      attempt,
      order: {
        ...order,
        status: "pending_fulfillment",
        fulfillmentLeaseToken: leaseToken,
        fulfillmentLeaseExpiresAt: leaseExpiresAt,
        fulfillmentAttempt: attempt
      }
    };
  });
}

const ORDER_STATUS_RANK = {
  paid: 0,
  pending_fulfillment: 1,
  submitted_to_printer: 2,
  printing: 3,
  shipped: 4,
  delivered: 5
};

function chooseMonotonicOrderStatus(currentStatus, incomingStatus) {
  const current = String(currentStatus || "");
  const incoming = String(incomingStatus || "");
  if (!incoming) return current || null;
  if (!current) return incoming;
  if (current === "delivered") return "delivered";
  if (current === "shipped") {
    return incoming === "delivered" ? "delivered" : "shipped";
  }
  if (current === "failed") return "failed";
  if (incoming === "failed") return "failed";

  const currentRank = ORDER_STATUS_RANK[current];
  const incomingRank = ORDER_STATUS_RANK[incoming];
  if (currentRank == null) return incoming;
  if (incomingRank == null) return current;
  return incomingRank >= currentRank ? incoming : current;
}

function appendLuluStatusHistory(existingHistory, {
  status,
  trackingUrl = null,
  source = "lulu_sync",
  timestamp = new Date().toISOString()
}, limit = LULU_STATUS_HISTORY_LIMIT) {
  const maxEntries = Math.max(1, Number(limit) || LULU_STATUS_HISTORY_LIMIT);
  const history = Array.isArray(existingHistory) ? existingHistory.slice(-maxEntries) : [];
  const normalized = {
    status: String(status || "UNKNOWN"),
    timestamp,
    trackingUrl: trackingUrl || null,
    source
  };
  const last = history[history.length - 1];
  if (last && String(last.status || "UNKNOWN") === normalized.status &&
      (last.trackingUrl || null) === normalized.trackingUrl &&
      String(last.source || "") === normalized.source) {
    return history;
  }
  return [...history, normalized].slice(-maxEntries);
}

function missingCartSessionDisposition({ attemptStripeSessionId, existingOrderCount }) {
  const recoveredSessionId = String(attemptStripeSessionId || "").trim();
  if (recoveredSessionId) return { action: "recover_session", sessionId: recoveredSessionId };
  if (Number(existingOrderCount || 0) > 0) return { action: "mark_paid" };
  return { action: "mark_abandoned" };
}

module.exports = {
  FULFILLMENT_LEASE_MILLIS,
  LULU_STATUS_HISTORY_LIMIT,
  appendLuluStatusHistory,
  buildPaidArtifactSnapshot,
  buildSingleBookOrderRecords,
  chooseMonotonicOrderStatus,
  claimOrderForFulfillment,
  commitSingleBookOrderOnce,
  fulfillmentClaimDecision,
  missingCartSessionDisposition,
  stripeSessionOrderId
};
