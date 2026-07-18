#!/usr/bin/env node
/**
 * One-off backfill: writes memoryIndex/{memoryId} -> { ownerId } for every existing
 * users/{uid}/memories/{memoryId} doc, so QR codes in already-printed books resolve
 * for the family access flow. New memories are indexed by the onMemoryDisplayNaming
 * trigger; this covers everything created before that trigger shipped.
 *
 * Run from functions/: node scripts/backfill-memory-index.js
 * Add --dry-run to count without writing.
 *
 * Requires: gcloud auth application-default login (or GOOGLE_APPLICATION_CREDENTIALS)
 */

const admin = require("firebase-admin");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "memoirai-7db06";
const DRY_RUN = process.argv.includes("--dry-run");

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

async function main() {
  let indexed = 0;
  let skipped = 0;
  let batch = db.batch();
  let batchSize = 0;

  const snapshot = await db.collectionGroup("memories").get();
  console.log(`Found ${snapshot.size} memory docs across all users.`);

  for (const doc of snapshot.docs) {
    const ownerRef = doc.ref.parent.parent;
    if (!ownerRef) {
      skipped += 1;
      continue;
    }
    if (DRY_RUN) {
      indexed += 1;
      continue;
    }
    batch.set(
      db.collection("memoryIndex").doc(doc.id),
      {
        ownerId: ownerRef.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );
    indexed += 1;
    batchSize += 1;
    if (batchSize >= 400) {
      await batch.commit();
      batch = db.batch();
      batchSize = 0;
      console.log(`  committed ${indexed} so far…`);
    }
  }

  if (!DRY_RUN && batchSize > 0) {
    await batch.commit();
  }

  console.log(`${DRY_RUN ? "[dry run] would index" : "Indexed"} ${indexed} memories, skipped ${skipped}.`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("Backfill failed:", e);
    process.exit(1);
  });
