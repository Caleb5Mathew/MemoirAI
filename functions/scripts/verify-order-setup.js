#!/usr/bin/env node
/**
 * Verifies book ordering setup is complete.
 * Run from functions/: node scripts/verify-order-setup.js
 */

const admin = require("firebase-admin");
const PROJECT_ID = process.env.GCLOUD_PROJECT || "memoirai-7db06";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

async function main() {
  const checks = [];
  let allOk = true;

  // 1. Check config/pricing exists
  try {
    const snap = await db.collection("config").doc("pricing").get();
    if (snap.exists && snap.data()?.kidsBook) {
      checks.push({ ok: true, msg: "config/pricing document exists" });
    } else {
      checks.push({ ok: false, msg: "config/pricing missing. Run: node scripts/seed-pricing-config.js" });
      allOk = false;
    }
  } catch (e) {
    checks.push({ ok: false, msg: `config/pricing: ${e.message}` });
    allOk = false;
  }

  // 2. Firebase secrets - we can't read them directly, but we can note they're needed
  checks.push({ ok: true, msg: "Secrets: Run ./scripts/setup-book-ordering-secrets.sh if not done" });

  // 3. Check if any books exist (sanity)
  try {
    const booksSnap = await db.collectionGroup("bookVersions").limit(1).get();
    checks.push({ ok: true, msg: `Firestore: ${booksSnap.empty ? "no books yet" : "bookVersions accessible"}` });
  } catch (e) {
    checks.push({ ok: false, msg: `Firestore: ${e.message}` });
  }

  console.log("\n--- Book Ordering Setup Check ---\n");
  checks.forEach((c) => {
    console.log(c.ok ? "✅" : "❌", c.msg);
  });
  console.log("");
  if (!allOk) {
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
