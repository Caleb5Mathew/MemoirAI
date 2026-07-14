/**
 * Mirrors paid / in-flight print orders into users/{uid}/purchasedBooks/{orderId} for ops + support.
 */

const admin = require("firebase-admin");
const { ensureBookVersionArtifactUrls } = require("./storageArtifactUrls");

const MIRROR_STATUSES = new Set([
  "paid",
  "pending_fulfillment",
  "submitted_to_printer",
  "printing",
  "shipped",
  "delivered",
  "failed",
  "lulu_failed"
]);

function printTitleFromBookVersionRecord(record) {
  const rec = record && typeof record === "object" ? record : {};
  const pt = rec.printTitle != null ? String(rec.printTitle).trim() : "";
  if (pt) {
    return pt;
  }
  const pages = Array.isArray(rec.pages) ? rec.pages : [];
  const first = pages[0];
  const t = first && first.title != null ? String(first.title).trim() : "";
  return t || null;
}

function dimensionsLabelFromBookRecord(bv) {
  const w = Number(bv.pageWidth || 612);
  const h = Number(bv.pageHeight || 792);
  return w > h ? "11x8.5\"" : "8.5x11\"";
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {import("@google-cloud/storage").Bucket} bucket
 * @returns {(event: import("firebase-functions/v2/firestore").FirestoreEvent<import("firebase-functions/v2/firestore").Change<FirebaseFirestore.DocumentSnapshot>>) => Promise<void>}
 */
function createOrderMirrorHandler(db, bucket) {
  return async (event) => {
    const afterSnap = event.data.after;
    if (!afterSnap.exists) {
      return;
    }
    const after = afterSnap.data() || {};
    const status = String(after.status || "");
    if (!MIRROR_STATUSES.has(status)) {
      return;
    }
    const userId = event.params.userId;
    const orderId = event.params.orderId;
    const bookVersionId = after.bookVersionId != null ? String(after.bookVersionId).trim() : "";
    if (!bookVersionId) {
      return;
    }

    try {
      await ensureBookVersionArtifactUrls(db, bucket, userId, bookVersionId);
    } catch (e) {
      console.warn("purchasedBooks mirror: ensureBookVersionArtifactUrls failed", userId, bookVersionId, e);
    }

    const bvSnap = await db
      .collection("users")
      .doc(userId)
      .collection("bookVersions")
      .doc(bookVersionId)
      .get();
    const bv = bvSnap.exists ? bvSnap.data() || {} : {};

    const purchaseRef = db.collection("users").doc(userId).collection("purchasedBooks").doc(orderId);
    const existingSnap = await purchaseRef.get();
    const ex = existingSnap.exists ? existingSnap.data() || {} : {};

    const coverURL = after.coverURL || bv.coverURL || null;
    const pdfURL = after.pdfURL || bv.pdfURL || null;
    const coverStoragePath = after.coverPdfStoragePath || bv.coverStoragePath || null;
    const pdfStoragePath = after.interiorPdfStoragePath || bv.pdfStoragePath || null;

    /** @type {Record<string, any>} */
    const updates = {
      purchaseId: orderId,
      orderId,
      userId,
      userHandle: bv.userHandle || after.userHandle || null,
      bookVersionId,
      bookDisplayName: bv.bookDisplayName || after.bookDisplayName || null,
      printTitle: printTitleFromBookVersionRecord(bv) || after.printTitle || null,
      productOptionId: after.selectedProductOptionId || null,
      productTitle: after.productTitle || null,
      dimensionsLabel: bv.pageWidth != null ? dimensionsLabelFromBookRecord(bv) : null,
      pageCount: bv.pageCount != null ? bv.pageCount : (Array.isArray(bv.pages) ? bv.pages.length : null),
      coverStoragePath,
      pdfStoragePath,
      coverURL,
      pdfURL,
      lineTotalCents: after.lineTotalCents != null ? after.lineTotalCents : null,
      unitCents: after.unitCents != null ? after.unitCents : null,
      quantity: after.quantity != null ? after.quantity : 1,
      currency: after.pricing && after.pricing.currency ? String(after.pricing.currency) : "usd",
      stripeSessionId: after.stripeSessionId || null,
      stripePaymentIntentId: after.stripePaymentIntentId || null,
      cartOrderGroupId: after.cartOrderGroupId || null,
      customerEmail: after.customerEmail || null,
      shippingAddress: after.shippingAddress || null,
      shippingLevel: after.shippingLevel || null,
      luluPrintJobId: after.luluPrintJobId || null,
      luluTrackingUrl: after.luluTrackingUrl || null,
      luluStatusHistory: Array.isArray(after.luluStatusHistory) ? after.luluStatusHistory : [],
      luluError: after.luluError || null,
      isTestOrder: Boolean(after.isTestOrder),
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    if (!ex.paidAt && status === "paid") {
      updates.paidAt = admin.firestore.FieldValue.serverTimestamp();
    }
    if (!ex.fulfilledAt && (status === "pending_fulfillment" || status === "submitted_to_printer")) {
      updates.fulfilledAt = admin.firestore.FieldValue.serverTimestamp();
    }
    if (!ex.shippedAt && status === "shipped") {
      updates.shippedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    if (!ex.deliveredAt && status === "delivered") {
      updates.deliveredAt = admin.firestore.FieldValue.serverTimestamp();
    }

    await purchaseRef.set(updates, { merge: true });
  };
}

module.exports = {
  createOrderMirrorHandler,
  MIRROR_STATUSES
};
