#!/usr/bin/env node
/**
 * Machine-readable assertions for print order flow milestones.
 * Run from functions/: node scripts/check-order-assertions.js <mode> [args]
 *
 * Modes:
 *   preflight <bookVersionId>     — Book is checkout-ready (rendered + PDF/cover paths/URLs)
 *   post-payment <orderId>        — Order doc after Stripe webhook (paid + required fields)
 *   post-fulfillment <orderId>    — After fulfillOrder (Lulu job id + submitted_to_printer or later)
 *   lulu-status <orderId>         — Snapshot of Lulu fields (history, tracking)
 *
 * Prints lines: CHECK_RESULT milestone=... name=... ok=true|false [detail=...]
 * Exit 0 if all assertions pass, 1 otherwise.
 */

const admin = require("firebase-admin");

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCLOUD_PROJECT_ID || "memoirai-7db06";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

function result(milestone, name, ok, detail = "") {
  const d = detail ? ` detail=${JSON.stringify(String(detail))}` : "";
  console.log(`CHECK_RESULT milestone=${milestone} name=${name} ok=${ok}${d}`);
}

async function findBookVersion(bookVersionId) {
  const usersSnap = await db.collection("users").get();
  for (const userDoc of usersSnap.docs) {
    const ref = userDoc.ref.collection("bookVersions").doc(bookVersionId);
    const snapshot = await ref.get();
    if (snapshot.exists) {
      return { doc: snapshot.data(), userId: userDoc.id };
    }
  }
  return { doc: null, userId: null };
}

async function findOrderByOrderId(orderId) {
  const snap = await db.collectionGroup("orders").where("orderId", "==", orderId).limit(1).get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  return {
    ref: doc.ref,
    data: doc.data(),
    userId: doc.ref.parent?.parent?.id || null
  };
}

function assertPreflight(bookVersionId, doc, userId) {
  const m = "preflight";
  let allOk = true;

  if (!doc) {
    result(m, "book_exists", false, `bookVersionId not found: ${bookVersionId}`);
    return false;
  }

  result(m, "book_user_path", true, `users/${userId}/bookVersions/${bookVersionId}`);

  const rs = doc.renderStatus;
  const rendered = rs === "rendered";
  result(m, "renderStatus_rendered", rendered, rendered ? rs : `got ${rs}`);
  if (!rendered) allOk = false;

  const hasPdfUrl = Boolean(doc.pdfURL && String(doc.pdfURL).trim());
  result(m, "pdfURL", hasPdfUrl, hasPdfUrl ? "set" : "missing");
  if (!hasPdfUrl) allOk = false;

  const hasCoverUrl = Boolean(doc.coverURL && String(doc.coverURL).trim());
  result(m, "coverURL", hasCoverUrl, hasCoverUrl ? "set" : "missing");
  if (!hasCoverUrl) allOk = false;

  const hasPdfPath = Boolean(doc.pdfStoragePath && String(doc.pdfStoragePath).trim());
  result(m, "pdfStoragePath", hasPdfPath, hasPdfPath ? doc.pdfStoragePath : "missing");
  if (!hasPdfPath) allOk = false;

  const hasCoverPath = Boolean(doc.coverStoragePath && String(doc.coverStoragePath).trim());
  result(m, "coverStoragePath", hasCoverPath, hasCoverPath ? doc.coverStoragePath : "missing");
  if (!hasCoverPath) allOk = false;

  const uidInPath = userId && String(doc.pdfStoragePath || "").includes(userId);
  const bidInPath =
    userId &&
    String(doc.pdfStoragePath || "").includes(bookVersionId) &&
    String(doc.coverStoragePath || "").includes(bookVersionId);
  result(m, "paths_contain_userId", Boolean(uidInPath), uidInPath ? "ok" : "check manually");
  result(m, "paths_contain_bookVersionId", Boolean(bidInPath), bidInPath ? "ok" : "check manually");

  return allOk;
}

function assertPostPayment(orderId, row) {
  const m = "post-payment";
  if (!row) {
    result(m, "order_exists", false, `orderId not found: ${orderId}`);
    return false;
  }

  const d = row.data;
  let allOk = true;

  result(m, "order_user_path", true, row.ref?.path || "");

  const paid = d.status === "paid";
  result(m, "status_paid", paid, d.status || "(none)");
  if (!paid) allOk = false;

  const hasBook = Boolean(d.bookVersionId);
  result(m, "bookVersionId", hasBook, d.bookVersionId || "");
  if (!hasBook) allOk = false;

  const hasSession = Boolean(d.stripeSessionId);
  result(m, "stripeSessionId", hasSession, hasSession ? "set" : "missing");
  if (!hasSession) allOk = false;

  const hasCoverPath = Boolean(d.coverPdfStoragePath);
  const hasInteriorPath = Boolean(d.interiorPdfStoragePath);
  result(m, "coverPdfStoragePath", hasCoverPath, d.coverPdfStoragePath || "missing");
  result(m, "interiorPdfStoragePath", hasInteriorPath, d.interiorPdfStoragePath || "missing");
  if (!hasCoverPath || !hasInteriorPath) allOk = false;

  const ship = d.shippingAddress;
  const hasShip =
    ship &&
    (ship.street1 || ship.city) &&
    (ship.postcode || ship.stateCode);
  result(m, "shippingAddress", Boolean(hasShip), hasShip ? "present" : JSON.stringify(ship || {}));
  if (!hasShip) allOk = false;

  const cents = d.pricing?.totalCents;
  const hasPricing = typeof cents === "number" && cents > 0;
  result(m, "pricing_totalCents", hasPricing, hasPricing ? String(cents) : String(cents));
  if (!hasPricing) allOk = false;

  result(
    m,
    "isTestOrder_flag",
    true,
    d.isTestOrder ? "true (Stripe test — Lulu autoFulfill skipped)" : "false (live — autoFulfillPaidOrder may run)"
  );
  if (d.isTestOrder === true) {
    console.log(
      "\n⚠️  Note: isTestOrder=true (Stripe test mode). autoFulfillPaidOrder skips Lulu; fulfillOrder rejects test orders. Use live Stripe + webhook to exercise printing.\n"
    );
  }

  return allOk;
}

/** Status values expected after successful fulfillOrder or Lulu webhooks */
const AFTER_SUBMIT_STATUSES = new Set([
  "submitted_to_printer",
  "printing",
  "shipped",
  "delivered",
  "pending_fulfillment"
]);

function assertPostFulfillment(orderId, row) {
  const m = "post-fulfillment";
  if (!row) {
    result(m, "order_exists", false, `orderId not found: ${orderId}`);
    return false;
  }

  const d = row.data;
  let allOk = true;

  const hasJob = Boolean(d.luluPrintJobId);
  result(m, "luluPrintJobId", hasJob, d.luluPrintJobId ? String(d.luluPrintJobId) : "missing");
  if (!hasJob) allOk = false;

  const st = d.status;
  if (st === "paid") {
    result(
      m,
      "status_submitted_to_printer",
      false,
      "still paid — wait for autoFulfillPaidOrder or call fulfillOrder callable (if not test order)"
    );
    allOk = false;
  } else {
    const okStatus = AFTER_SUBMIT_STATUSES.has(st);
    result(m, "status_submitted_to_printer", okStatus, st || "(none)");
    if (!okStatus) allOk = false;
  }

  return allOk;
}

async function printLuluStatus(orderId) {
  const row = await findOrderByOrderId(orderId);
  const m = "lulu-status";
  if (!row) {
    result(m, "order_exists", false, orderId);
    return false;
  }
  const d = row.data;
  console.log("\n--- Lulu / order snapshot ---");
  console.log(`  status: ${d.status}`);
  console.log(`  luluPrintJobId: ${d.luluPrintJobId ?? "(none)"}`);
  console.log(`  luluTrackingUrl: ${d.luluTrackingUrl ?? "(none)"}`);
  const hist = Array.isArray(d.luluStatusHistory) ? d.luluStatusHistory : [];
  console.log(`  luluStatusHistory entries: ${hist.length}`);
  hist.slice(-5).forEach((h, i) => {
    console.log(`    [${i}]`, JSON.stringify(h));
  });
  result(m, "has_tracking_or_history", Boolean(d.luluTrackingUrl || hist.length), "");
  return true;
}

function printKnownGaps() {
  console.log(`
=== Print order behavior (current codebase) ===
- On checkout.session.completed, stripeWebhook creates users/{uid}/orders/{orderId} with status paid.
- autoFulfillPaidOrder (Firestore trigger) submits to Lulu when status is paid, isTestOrder is false,
  and luluPrintJobId is absent. Stripe test mode sets isTestOrder=true — autoFulfill skips Lulu (expected).
- fulfillOrder (callable) rejects isTestOrder=true; use for manual submission / recovery on live orders.
- admin-orders.js fulfill-confirm may set pending_fulfillment; fulfillOrder expects status paid — see ORDER_SETUP_GUIDE.md.
================================
`);
}

async function main() {
  const [,, mode, id] = process.argv;
  if (!mode || !id) {
    console.error(
      "Usage:\n" +
        "  node scripts/check-order-assertions.js preflight <bookVersionId>\n" +
        "  node scripts/check-order-assertions.js post-payment <orderId>\n" +
        "  node scripts/check-order-assertions.js post-fulfillment <orderId>\n" +
        "  node scripts/check-order-assertions.js lulu-status <orderId>\n"
    );
    process.exit(1);
  }

  if (mode === "preflight") {
    printKnownGaps();
  }

  let ok = true;

  if (mode === "preflight") {
    const { doc, userId } = await findBookVersion(id);
    ok = assertPreflight(id, doc, userId);
  } else if (mode === "post-payment") {
    const row = await findOrderByOrderId(id);
    ok = assertPostPayment(id, row);
  } else if (mode === "post-fulfillment") {
    const row = await findOrderByOrderId(id);
    ok = assertPostFulfillment(id, row);
  } else if (mode === "lulu-status") {
    await printLuluStatus(id);
    process.exit(0);
  } else {
    console.error(`Unknown mode: ${mode}`);
    process.exit(1);
  }

  console.log(`\nCHECK_SUMMARY mode=${mode} ok=${ok}\n`);
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
