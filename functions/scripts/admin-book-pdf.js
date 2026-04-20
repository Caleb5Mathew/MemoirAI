#!/usr/bin/env node
/**
 * MemoirAI Admin: List books, check render status, generate PDFs
 *
 * Run: node scripts/admin-book-pdf.js [command] [options]
 *
 * Commands:
 *   list [userId]           List bookVersions (optionally for one user)
 *   status <bookVersionId>  Show status of one book
 *   trigger <bookVersionId> [userId]  Trigger PDF generation (requires userId if not in Firestore)
 *   download <bookVersionId> [outputPath]  Download PDF to file
 *   verify <bookVersionId>  Download, validate PDF (page count, structure), report pass/fail
 *   latest                  Print most recent bookVersionId (for scripting)
 *
 * Requires: firebase login (Application Default Credentials) or GOOGLE_APPLICATION_CREDENTIALS
 * Set project: Firebase project is memoirai-7db06 (from .firebaserc or --project)
 */

const admin = require("firebase-admin");
const { PDFDocument } = require("pdf-lib");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "memoirai-7db06";
const STORAGE_BUCKET = process.env.FIREBASE_STORAGE_BUCKET || "memoirai-7db06.firebasestorage.app";

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: PROJECT_ID,
    storageBucket: STORAGE_BUCKET
  });
}

const db = admin.firestore();
const bucket = admin.storage().bucket();

/** Try collection group query; fallback to per-user iteration if index missing. */
async function listBooksViaCollectionGroup() {
  try {
    return await db.collectionGroup("bookVersions")
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();
  } catch (err) {
    if (err.code === 9 || (err.message && err.message.includes("FAILED_PRECONDITION"))) {
      return await listBooksByIteratingUsers(50);
    }
    throw err;
  }
}

/** Fallback: iterate users, get bookVersions per user, merge and sort. */
async function listBooksByIteratingUsers(limit) {
  const usersSnap = await db.collection("users").get();
  const all = [];
  for (const userDoc of usersSnap.docs) {
    const snap = await userDoc.ref.collection("bookVersions")
      .orderBy("createdAt", "desc")
      .limit(limit)
      .get();
    snap.docs.forEach((d) => all.push(d));
  }
  all.sort((a, b) => {
    const ta = a.data().createdAt?.toMillis?.() ?? 0;
    const tb = b.data().createdAt?.toMillis?.() ?? 0;
    return tb - ta;
  });
  return { docs: all.slice(0, limit), size: Math.min(all.length, limit), empty: all.length === 0 };
}

async function listBooks(userId = null) {
  let snapshot;
  if (userId) {
    const query = db.collection("users").doc(userId).collection("bookVersions")
      .orderBy("createdAt", "desc")
      .limit(50);
    snapshot = await query.get();
  } else {
    snapshot = await listBooksViaCollectionGroup();
  }

  console.log(`\n--- Book Versions (${snapshot.size} found) ---\n`);
  snapshot.docs.forEach((doc) => {
    const d = doc.data();
    const uid = doc.ref.parent.parent?.id || "?";
    console.log(`  ${doc.id}`);
    console.log(`    user: ${uid}`);
    console.log(`    pages: ${d.pageCount ?? "?"}, status: ${d.renderStatus ?? "?"}, style: ${d.artStyle ?? "?"}`);
    console.log(`    dims: ${d.pageWidth ?? "?"}x${d.pageHeight ?? "?"}pt, created: ${d.createdAt?.toDate?.()?.toISOString?.() ?? "?"}`);
    if (d.pdfURL) console.log(`    PDF: ${d.pdfURL.substring(0, 70)}...`);
    else console.log(`    PDF: (not rendered)`);
    console.log("");
  });
}

async function getLatestBookId() {
  let snapshot;
  try {
    snapshot = await db.collectionGroup("bookVersions")
      .orderBy("createdAt", "desc")
      .limit(1)
      .get();
  } catch (err) {
    if (err.code === 9 || (err.message && err.message.includes("FAILED_PRECONDITION"))) {
      const fallback = await listBooksByIteratingUsers(1);
      snapshot = { docs: fallback.docs, empty: fallback.empty };
    } else {
      throw err;
    }
  }
  if (snapshot.empty || !snapshot.docs.length) return null;
  console.log(snapshot.docs[0].id);
}

async function showStatus(bookVersionId) {
  const { doc, userId } = await findBookVersion(bookVersionId);
  if (!doc) {
    console.error(`Book version not found: ${bookVersionId}`);
    process.exit(1);
  }

  console.log(`\n--- Status: ${bookVersionId} ---`);
  console.log(`  user: ${userId}`);
  console.log(`  pages: ${doc.pageCount}, status: ${doc.renderStatus ?? "?"}`);
  console.log(`  dims: ${doc.pageWidth}x${doc.pageHeight}pt`);
  console.log(`  pdfURL: ${doc.pdfURL ?? "(none)"}`);
  console.log(`  coverURL: ${doc.coverURL ?? "(none)"}`);
  console.log(`  coverStoragePath: ${doc.coverStoragePath ?? "(none)"}`);
  console.log(`  renderError: ${doc.renderError ?? "(none)"}`);
  console.log(`  renderAttemptCount: ${doc.renderAttemptCount ?? 0}`);
  const pages = Array.isArray(doc.pages) ? doc.pages : [];
  pages.sort((a, b) => (a.pageIndex || 0) - (b.pageIndex || 0));
  console.log(`\n  Page artifacts:`);
  pages.forEach((p, i) => {
    const path = p.imageStoragePath || p.renderedPageStoragePath;
    console.log(`    [${i}] type=${p.type}, path=${path ? "yes" : "MISSING"}`);
  });
  console.log("");
}

async function listOrders(userId = null) {
  let snapshot;
  if (userId) {
    snapshot = await db.collection("users").doc(userId).collection("orders")
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();
  } else {
    snapshot = await db.collectionGroup("orders")
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();
  }

  console.log(`\n--- Print Orders (${snapshot.size} found) ---\n`);
  snapshot.docs.forEach((doc) => {
    const d = doc.data();
    const uid = doc.ref.parent?.parent?.id || "?";
    console.log(`  ${d.orderId || doc.id}`);
    console.log(`    user: ${uid}`);
    console.log(`    bookVersionId: ${d.bookVersionId ?? "?"}`);
    console.log(`    status: ${d.status ?? "?"}`);
    console.log(`    luluPrintJobId: ${d.luluPrintJobId ?? "(none)"}`);
    console.log(`    total: $${((d.pricing?.totalCents ?? 0) / 100).toFixed(2)} ${d.pricing?.currency ?? "usd"}`);
    console.log(`    created: ${d.createdAt?.toDate?.()?.toISOString?.() ?? "?"}`);
    if (d.luluTrackingUrl) console.log(`    tracking: ${d.luluTrackingUrl}`);
    console.log("");
  });
}

async function showOrderStatus(orderId) {
  const snap = await db.collectionGroup("orders")
    .where("orderId", "==", orderId)
    .limit(1)
    .get();

  if (snap.empty) {
    console.error(`Order not found: ${orderId}`);
    process.exit(1);
  }

  const doc = snap.docs[0].data();
  const userId = snap.docs[0].ref.parent?.parent?.id || "?";

  console.log(`\n--- Order: ${orderId} ---`);
  console.log(`  user: ${userId}`);
  console.log(`  bookVersionId: ${doc.bookVersionId}`);
  console.log(`  status: ${doc.status}`);
  console.log(`  luluPrintJobId: ${doc.luluPrintJobId ?? "(none)"}`);
  console.log(`  stripeSessionId: ${doc.stripeSessionId ?? "(none)"}`);
  console.log(`  total: $${((doc.pricing?.totalCents ?? 0) / 100).toFixed(2)}`);
  if (doc.luluTrackingUrl) console.log(`  tracking: ${doc.luluTrackingUrl}`);
  if (doc.luluError) console.log(`  luluError: ${doc.luluError}`);
  console.log(`  shipping: ${doc.shippingAddress?.city ?? "?"}, ${doc.shippingAddress?.postcode ?? "?"}`);
  console.log("");
}

async function generatePdfForBook(userId, bookVersionId) {
  const docRef = db.collection("users").doc(userId).collection("bookVersions").doc(bookVersionId);
  const snapshot = await docRef.get();
  if (!snapshot.exists) {
    throw new Error(`Book not found: ${bookVersionId}`);
  }
  const record = snapshot.data() || {};
  const pages = Array.isArray(record.pages) ? [...record.pages] : [];
  pages.sort((a, b) => (a.pageIndex || 0) - (b.pageIndex || 0));
  if (!pages.length) {
    throw new Error("No pages");
  }

  const widthPt = Number(record.pageWidth || 612);
  const heightPt = Number(record.pageHeight || 792);
  const pdfDoc = await PDFDocument.create();

  for (let i = 0; i < pages.length; i += 1) {
    const page = pages[i] || {};
    const storagePath = page.imageStoragePath || page.renderedPageStoragePath;
    if (!storagePath) {
      throw new Error(`Missing storage path at page ${i}`);
    }
    const [imageBytes] = await bucket.file(storagePath).download();
    const isJpeg = storagePath.toLowerCase().endsWith(".jpg") || storagePath.toLowerCase().endsWith(".jpeg");
    const embeddedImage = isJpeg
      ? await pdfDoc.embedJpg(imageBytes)
      : await pdfDoc.embedPng(imageBytes);
    const pdfPage = pdfDoc.addPage([widthPt, heightPt]);
    pdfPage.drawImage(embeddedImage, { x: 0, y: 0, width: widthPt, height: heightPt });
  }

  const pdfBytes = await pdfDoc.save();
  const pdfStoragePath = `users/${userId}/bookVersions/${bookVersionId}/book.pdf`;
  const crypto = require("crypto");
  const downloadToken = crypto.randomUUID();
  const file = bucket.file(pdfStoragePath);
  await file.save(Buffer.from(pdfBytes), {
    metadata: {
      contentType: "application/pdf",
      metadata: {
        firebaseStorageDownloadTokens: downloadToken
      }
    },
    resumable: false
  });
  const encodedPath = encodeURIComponent(pdfStoragePath);
  const pdfURL = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${downloadToken}`;

  await docRef.set({
    renderStatus: "rendered",
    renderError: admin.firestore.FieldValue.delete(),
    renderedAt: admin.firestore.FieldValue.serverTimestamp(),
    pdfStoragePath,
    pdfURL,
    pdfPageCount: pages.length,
    pdfBytes: pdfBytes.length
  }, { merge: true });

  console.log(`\n✅ PDF generated: ${pdfURL}`);
  console.log(`   Size: ${(pdfBytes.length / 1024).toFixed(1)} KB\n`);
  return pdfURL;
}

async function triggerPdf(bookVersionId, userIdHint) {
  const { userId: found } = await findBookVersion(bookVersionId);
  const userId = userIdHint || found;
  if (!userId) {
    console.error("Book not found. Provide userId: admin-book-pdf.js trigger <bookVersionId> <userId>");
    process.exit(1);
  }
  await generatePdfForBook(userId, bookVersionId);
}

async function downloadPdf(bookVersionId, outputPath) {
  const { doc } = await findBookVersion(bookVersionId);
  if (!doc?.pdfURL) {
    console.error(`No PDF found for ${bookVersionId}. Run 'trigger' first to generate.`);
    process.exit(1);
  }

  const res = await fetch(doc.pdfURL);
  if (!res.ok) {
    console.error(`Download failed: ${res.status}`);
    process.exit(1);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  const out = outputPath || path.join(process.cwd(), `MemoirAI_${bookVersionId}.pdf`);
  fs.writeFileSync(out, buf);
  console.log(`\n✅ Downloaded to ${out} (${(buf.length / 1024).toFixed(1)} KB)\n`);
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

async function downloadCover(bookVersionId, outputPath) {
  const { doc } = await findBookVersion(bookVersionId);
  if (!doc?.coverURL) {
    console.error(`No cover PDF found for ${bookVersionId}. Ensure cover was generated (Kids Book with headshot).`);
    process.exit(1);
  }

  const res = await fetch(doc.coverURL);
  if (!res.ok) {
    console.error(`Download failed: ${res.status}`);
    process.exit(1);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  const out = outputPath || path.join(process.cwd(), `MemoirAI_${bookVersionId}_cover.pdf`);
  fs.writeFileSync(out, buf);
  console.log(`\n✅ Cover downloaded to ${out} (${(buf.length / 1024).toFixed(1)} KB)\n`);
}

async function verifyPdf(bookVersionId) {
  const { doc } = await findBookVersion(bookVersionId);
  if (!doc?.pdfURL) {
    console.error(`\n❌ No PDF found for ${bookVersionId}. Run 'trigger' first to generate.\n`);
    process.exit(1);
  }

  const res = await fetch(doc.pdfURL);
  if (!res.ok) {
    console.error(`\n❌ Download failed: ${res.status}\n`);
    process.exit(1);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  let pdfDoc;
  try {
    pdfDoc = await PDFDocument.load(buf);
  } catch (err) {
    console.error(`\n❌ Invalid PDF: ${err.message}\n`);
    process.exit(1);
  }

  const pages = pdfDoc.getPages();
  const pageCount = pages.length;
  const expectedPages = doc.pageCount || 0;
  const firstPage = pages[0];
  const width = firstPage ? Math.round(firstPage.getWidth()) : "?";
  const height = firstPage ? Math.round(firstPage.getHeight()) : "?";

  console.log(`\n--- Verify: ${bookVersionId} ---`);
  console.log(`  Page count: ${pageCount} (expected: ${expectedPages})`);
  console.log(`  First page dims: ${width} x ${height} pt`);
  console.log(`  PDF size: ${(buf.length / 1024).toFixed(1)} KB`);

  if (pageCount > 0 && (!expectedPages || pageCount === expectedPages)) {
    console.log(`  ✅ PASSED\n`);
    return;
  }
  if (expectedPages && pageCount !== expectedPages) {
    console.log(`  ❌ FAILED: page count mismatch (got ${pageCount}, expected ${expectedPages})\n`);
    process.exit(1);
  }
  console.log(`  ✅ PASSED\n`);
}

async function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];

  if (!cmd || cmd === "help" || cmd === "-h" || cmd === "--help") {
    console.log(`
MemoirAI Admin Book PDF Tool

Usage: node scripts/admin-book-pdf.js <command> [options]

Commands:
  list [userId]              List book versions (all users or one user)
  status <bookVersionId>     Show detailed book status
  trigger <bookVersionId> [userId]   Generate PDF (finds userId if omitted)
  download <bookVersionId> [outputPath]  Download existing PDF
  download-cover <bookVersionId> [path]   Download cover PDF
  verify <bookVersionId>     Download and validate PDF structure
  latest                    Print most recent book ID (for scripting)
  orders list [userId]      List print orders (all users or one user)
  orders status <orderId>   Show order status and Lulu job info

Examples:
  node scripts/admin-book-pdf.js list
  node scripts/admin-book-pdf.js list GvgDuJiXL5YCdalwy9999Tr9MrS2
  node scripts/admin-book-pdf.js status 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420
  node scripts/admin-book-pdf.js trigger 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420
  node scripts/admin-book-pdf.js download 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420 ./mybook.pdf
  node scripts/admin-book-pdf.js download-cover 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420 ./cover.pdf
  node scripts/admin-book-pdf.js verify 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420
  node scripts/admin-book-pdf.js latest   # Get newest book ID for scripts
`);
    return;
  }

  try {
    if (cmd === "list") {
      await listBooks(args[1] || null);
    } else if (cmd === "status") {
      if (!args[1]) {
        console.error("Usage: status <bookVersionId>");
        process.exit(1);
      }
      await showStatus(args[1]);
    } else if (cmd === "trigger") {
      if (!args[1]) {
        console.error("Usage: trigger <bookVersionId> [userId]");
        process.exit(1);
      }
      await triggerPdf(args[1], args[2]);
    } else if (cmd === "download") {
      if (!args[1]) {
        console.error("Usage: download <bookVersionId> [outputPath]");
        process.exit(1);
      }
      await downloadPdf(args[1], args[2]);
    } else if (cmd === "download-cover") {
      if (!args[1]) {
        console.error("Usage: download-cover <bookVersionId> [outputPath]");
        process.exit(1);
      }
      await downloadCover(args[1], args[2]);
    } else if (cmd === "verify") {
      if (!args[1]) {
        console.error("Usage: verify <bookVersionId>");
        process.exit(1);
      }
      await verifyPdf(args[1]);
    } else if (cmd === "latest") {
      await getLatestBookId();
    } else if (cmd === "orders") {
      const subCmd = args[1];
      if (subCmd === "list") {
        await listOrders(args[2] || null);
      } else if (subCmd === "status") {
        if (!args[2]) {
          console.error("Usage: orders status <orderId>");
          process.exit(1);
        }
        await showOrderStatus(args[2]);
      } else {
        console.error("Usage: orders list [userId] | orders status <orderId>");
        process.exit(1);
      }
    } else {
      console.error(`Unknown command: ${cmd}`);
      process.exit(1);
    }
  } catch (err) {
    console.error(err.message || err);
    process.exit(1);
  }
}

main();
