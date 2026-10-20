#!/usr/bin/env node
// Metadata-only migration. Defaults to dry-run; use --apply to persist timestamps.
const admin = require("firebase-admin");
const { accountCreationTimestamp, updateMissingTimestamp } = require("../adminUserBrowser");

async function backfillCollection(db, collection, field, resolveTimestamp, apply, stats) {
  let cursor;
  for (;;) {
    let query = collection.orderBy(admin.firestore.FieldPath.documentId()).limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const doc of page.docs) {
      stats.scanned += 1;
      if (doc.data()[field] != null) continue;
      stats.missing += 1;
      const timestamp = await resolveTimestamp(doc);
      if (apply && await updateMissingTimestamp(db, doc.ref, field, timestamp)) stats.updated += 1;
    }
    if (page.docs.length < 100) break;
    cursor = page.docs[page.docs.length - 1];
  }
}

async function main() {
  const args = process.argv.slice(2);
  if (args.some(arg => !["--apply", "--dry-run"].includes(arg)) || args.length > 1) throw new Error("Use --dry-run (default) or --apply.");
  const apply = args.includes("--apply");
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "memoirai-7db06" });
  const db = admin.firestore();
  const stats = { users: { scanned: 0, missing: 0, updated: 0 }, books: { scanned: 0, missing: 0, updated: 0 }, memories: { scanned: 0, missing: 0, updated: 0 } };
  await backfillCollection(db, db.collection("users"), "accountCreatedAt", async doc => {
    let authUser;
    try { authUser = await admin.auth().getUser(doc.id); }
    catch (error) { if (error.code !== "auth/user-not-found") throw error; }
    return accountCreationTimestamp(authUser, doc.createTime);
  }, apply, stats.users);
  // Collection-group scans include subcollections under deleted or absent root documents.
  await backfillCollection(db, db.collectionGroup("bookVersions"), "createdAt", doc => doc.createTime, apply, stats.books);
  await backfillCollection(db, db.collectionGroup("memories"), "createdAt", doc => doc.createTime, apply, stats.memories);
  console.log(JSON.stringify({ mode: apply ? "apply" : "dry-run", ...stats }));
}

if (require.main === module) main().catch(error => { console.error("Date backfill failed:", error.code || error.name); process.exitCode = 1; });
module.exports = { backfillCollection };
