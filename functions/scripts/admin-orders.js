#!/usr/bin/env node
/**
 * Admin order management — list, inspect, and fulfill paid orders.
 *
 * Usage:
 *   GCLOUD_PROJECT=memoirai-7db06 node scripts/admin-orders.js list
 *   GCLOUD_PROJECT=memoirai-7db06 node scripts/admin-orders.js show <orderId>
 *   GCLOUD_PROJECT=memoirai-7db06 node scripts/admin-orders.js fulfill <orderId>
 */

const admin = require("firebase-admin");

const projectId = process.env.GCLOUD_PROJECT || "memoirai-7db06";
if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}
const db = admin.firestore();

async function listOrders(statusFilter) {
  const usersSnap = await db.collection("users").get();
  const orders = [];
  for (const userDoc of usersSnap.docs) {
    let q = userDoc.ref.collection("orders").orderBy("createdAt", "desc");
    if (statusFilter) {
      q = q.where("status", "==", statusFilter);
    }
    const ordersSnap = await q.get();
    for (const orderDoc of ordersSnap.docs) {
      const d = orderDoc.data();
      orders.push({
        orderId: d.orderId,
        userId: userDoc.id,
        status: d.status,
        bookVersionId: d.bookVersionId,
        isTestOrder: d.isTestOrder || false,
        totalCents: d.pricing?.totalCents,
        email: d.customerEmail || "(none)",
        createdAt: d.createdAt?.toDate?.()?.toISOString() || "(unknown)"
      });
    }
  }
  if (orders.length === 0) {
    console.log(statusFilter ? `No orders with status '${statusFilter}'.` : "No orders found.");
    return;
  }
  console.log(`\n${orders.length} order(s)${statusFilter ? ` with status '${statusFilter}'` : ""}:\n`);
  for (const o of orders) {
    const price = o.totalCents ? `$${(o.totalCents / 100).toFixed(2)}` : "N/A";
    const test = o.isTestOrder ? " [TEST]" : "";
    console.log(`  ${o.orderId}  ${o.status.padEnd(22)} ${price.padStart(8)}${test}`);
    console.log(`    user: ${o.userId}  book: ${o.bookVersionId}`);
    console.log(`    email: ${o.email}  created: ${o.createdAt}\n`);
  }
}

async function showOrder(orderId) {
  const usersSnap = await db.collection("users").get();
  for (const userDoc of usersSnap.docs) {
    const ref = userDoc.ref.collection("orders").doc(orderId);
    const snap = await ref.get();
    if (snap.exists) {
      console.log("\nOrder found:\n");
      console.log(JSON.stringify(snap.data(), null, 2));
      return;
    }
  }
  console.error(`Order '${orderId}' not found.`);
  process.exit(1);
}

async function fulfillOrder(orderId) {
  let orderRef = null;
  let orderData = null;
  let targetUserId = null;

  const usersSnap = await db.collection("users").get();
  for (const userDoc of usersSnap.docs) {
    const ref = userDoc.ref.collection("orders").doc(orderId);
    const snap = await ref.get();
    if (snap.exists) {
      orderRef = ref;
      orderData = snap.data();
      targetUserId = userDoc.id;
      break;
    }
  }

  if (!orderData) {
    console.error(`Order '${orderId}' not found.`);
    process.exit(1);
  }

  if (orderData.status !== "paid") {
    console.error(`Order status is '${orderData.status}', expected 'paid'. Cannot fulfill.`);
    process.exit(1);
  }

  if (orderData.isTestOrder) {
    console.error("This is a test order. Cannot submit to Lulu.");
    process.exit(1);
  }

  console.log("\nOrder to fulfill:");
  console.log(`  ID:       ${orderId}`);
  console.log(`  User:     ${targetUserId}`);
  console.log(`  Book:     ${orderData.bookVersionId}`);
  console.log(`  Email:    ${orderData.customerEmail || "(none)"}`);
  console.log(`  Total:    $${((orderData.pricing?.totalCents || 0) / 100).toFixed(2)}`);
  console.log(`  Shipping: ${JSON.stringify(orderData.shippingAddress)}`);
  console.log(`\n⚠️  This will create a REAL print job on Lulu and charge your Lulu account.`);
  console.log(`To proceed, run:\n`);
  console.log(`  GCLOUD_PROJECT=${projectId} node scripts/admin-orders.js fulfill-confirm ${orderId}\n`);
}

async function fulfillOrderConfirm(orderId) {
  console.log("NOTE: This script cannot call the Cloud Function with its secrets.");
  console.log("Use the Print Ops web UI (public/ops — see OPS_PRINT_QUEUE.md) or callable 'fulfillOrder'.");
  console.log(`\nAlternatively, use curl to call the function:\n`);
  console.log(`  # Get an ID token first, then:`);
  console.log(`  curl -X POST https://us-central1-${projectId}.cloudfunctions.net/fulfillOrder \\`);
  console.log(`    -H "Authorization: Bearer <ID_TOKEN>" \\`);
  console.log(`    -H "Content-Type: application/json" \\`);
  console.log(`    -d '{"data":{"orderId":"${orderId}","userId":"<USER_ID>"}}'`);
  console.log(`\nOr mark the order for fulfillment in Firestore manually:`);

  const usersSnap = await db.collection("users").get();
  for (const userDoc of usersSnap.docs) {
    const ref = userDoc.ref.collection("orders").doc(orderId);
    const snap = await ref.get();
    if (snap.exists && snap.data().status === "paid") {
      await ref.update({
        status: "pending_fulfillment",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`\n✅ Order '${orderId}' marked as 'pending_fulfillment'.`);
      console.log("The fulfillOrder Cloud Function can now be called from your admin panel or iOS app.\n");
      return;
    }
  }
  console.error(`Could not find or update order '${orderId}'.`);
  process.exit(1);
}

const [,, cmd, arg] = process.argv;

switch (cmd) {
  case "list":
    listOrders(arg).then(() => process.exit(0));
    break;
  case "show":
    if (!arg) { console.error("Usage: admin-orders.js show <orderId>"); process.exit(1); }
    showOrder(arg).then(() => process.exit(0));
    break;
  case "fulfill":
    if (!arg) { console.error("Usage: admin-orders.js fulfill <orderId>"); process.exit(1); }
    fulfillOrder(arg).then(() => process.exit(0));
    break;
  case "fulfill-confirm":
    if (!arg) { console.error("Usage: admin-orders.js fulfill-confirm <orderId>"); process.exit(1); }
    fulfillOrderConfirm(arg).then(() => process.exit(0));
    break;
  default:
    console.log("Admin order management\n");
    console.log("Commands:");
    console.log("  list [status]                 List all orders (optionally filter by status)");
    console.log("  show <orderId>                Show full order details");
    console.log("  fulfill <orderId>             Preview order before fulfillment");
    console.log("  fulfill-confirm <orderId>     Mark order for fulfillment\n");
    console.log("Examples:");
    console.log("  GCLOUD_PROJECT=memoirai-7db06 node scripts/admin-orders.js list");
    console.log("  GCLOUD_PROJECT=memoirai-7db06 node scripts/admin-orders.js list paid");
    console.log("  GCLOUD_PROJECT=memoirai-7db06 node scripts/admin-orders.js fulfill <orderId>\n");
    process.exit(0);
}
