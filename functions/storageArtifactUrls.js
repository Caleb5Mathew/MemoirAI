/**
 * Ensures Firebase Storage download token URLs exist for cover.pdf / book.pdf on a bookVersions doc.
 */

const admin = require("firebase-admin");
const crypto = require("crypto");

/**
 * @param {import("@google-cloud/storage").Bucket} bucket
 * @param {string} storagePath
 * @param {string} defaultContentType
 * @returns {Promise<string|null>}
 */
async function mintPermanentDownloadUrl(bucket, storagePath, defaultContentType) {
  const path = String(storagePath || "").trim();
  if (!path) return null;
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) return null;
  const [meta] = await file.getMetadata();
  let token =
    meta.metadata && meta.metadata.firebaseStorageDownloadTokens
      ? String(meta.metadata.firebaseStorageDownloadTokens).split(",")[0].trim()
      : "";
  if (!token) {
    token = crypto.randomUUID();
    await file.setMetadata({
      contentType: meta.contentType || defaultContentType,
      metadata: {
        ...(meta.metadata || {}),
        firebaseStorageDownloadTokens: token
      }
    });
  }
  const encodedPath = encodeURIComponent(path);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`;
}

/**
 * Mints missing coverURL / pdfURL on the book version document when paths exist.
 * @param {FirebaseFirestore.Firestore} db
 * @param {import("@google-cloud/storage").Bucket} bucket
 * @param {string} userId
 * @param {string} bookVersionId
 * @returns {Promise<Record<string, any>|null>} merged record fields (shallow) or null if doc missing
 */
async function ensureBookVersionArtifactUrls(db, bucket, userId, bookVersionId) {
  const docRef = db.collection("users").doc(userId).collection("bookVersions").doc(bookVersionId);
  const snap = await docRef.get();
  if (!snap.exists) return null;
  const record = snap.data() || {};
  const updates = {};
  let coverURL = record.coverURL ? String(record.coverURL) : "";
  let pdfURL = record.pdfURL ? String(record.pdfURL) : "";
  if (record.coverStoragePath && !coverURL) {
    const u = await mintPermanentDownloadUrl(bucket, record.coverStoragePath, "application/pdf");
    if (u) {
      updates.coverURL = u;
      coverURL = u;
    }
  }
  if (record.pdfStoragePath && !pdfURL) {
    const u = await mintPermanentDownloadUrl(bucket, record.pdfStoragePath, "application/pdf");
    if (u) {
      updates.pdfURL = u;
      pdfURL = u;
    }
  }
  if (Object.keys(updates).length > 0) {
    updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await docRef.set(updates, { merge: true });
  }
  return {
    ...record,
    ...updates,
    coverURL: coverURL || record.coverURL || null,
    pdfURL: pdfURL || record.pdfURL || null
  };
}

module.exports = {
  mintPermanentDownloadUrl,
  ensureBookVersionArtifactUrls
};
