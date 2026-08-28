/**
 * Ensures Firebase Storage download token URLs exist for cover.pdf / book.pdf on a bookVersions doc.
 */

const admin = require("firebase-admin");
const crypto = require("crypto");

const PDF_CONTENT_TYPE = "application/pdf";
const MAX_PDF_BYTES = 100 * 1024 * 1024;

function canonicalBookArtifactPaths(userId, bookVersionId) {
  const owner = String(userId || "").trim();
  const book = String(bookVersionId || "").trim();
  if (!owner || !book || owner.includes("/") || book.includes("/")) {
    throw new Error("Invalid book artifact identity");
  }
  const prefix = `users/${owner}/bookVersions/${book}`;
  return {
    cover: `${prefix}/cover.pdf`,
    interior: `${prefix}/book.pdf`
  };
}

function assertCanonicalBookArtifact(recordedPath, expectedPath, label) {
  const path = String(recordedPath || "").trim();
  if (path !== expectedPath) {
    throw new Error(`${label} storage path is not canonical`);
  }
  return path;
}

function assertPdfMetadata(metadata, label) {
  const contentType = String(metadata?.contentType || "").toLowerCase();
  const size = Number(metadata?.size);
  const generation = String(metadata?.generation || "").trim();
  if (contentType !== PDF_CONTENT_TYPE) {
    throw new Error(`${label} artifact is not a PDF`);
  }
  if (!Number.isFinite(size) || size <= 0 || size > MAX_PDF_BYTES) {
    throw new Error(`${label} artifact size is invalid`);
  }
  if (!generation) {
    throw new Error(`${label} artifact generation is missing`);
  }
  return { generation, size };
}

/**
 * @param {import("@google-cloud/storage").Bucket} bucket
 * @param {string} storagePath
 * @param {string} label
 * @returns {Promise<string|null>}
 */
async function mintPermanentDownloadArtifact(bucket, storagePath, label) {
  const path = String(storagePath || "").trim();
  if (!path) return null;
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) return null;
  const [meta] = await file.getMetadata();
  const validated = assertPdfMetadata(meta, label);
  let token =
    meta.metadata && meta.metadata.firebaseStorageDownloadTokens
      ? String(meta.metadata.firebaseStorageDownloadTokens).split(",")[0].trim()
      : "";
  if (!token) {
    token = crypto.randomUUID();
    await file.setMetadata(
      {
        contentType: PDF_CONTENT_TYPE,
        metadata: {
          ...(meta.metadata || {}),
          firebaseStorageDownloadTokens: token
        }
      },
      { preconditionOpts: { ifGenerationMatch: validated.generation } }
    );
  }
  const encodedPath = encodeURIComponent(path);
  return {
    url: `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`,
    generation: validated.generation,
    size: validated.size
  };
}

async function mintPermanentDownloadUrl(bucket, storagePath, label) {
  return (await mintPermanentDownloadArtifact(bucket, storagePath, label))?.url || null;
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
  const canonicalPaths = canonicalBookArtifactPaths(userId, bookVersionId);
  const coverStoragePath = assertCanonicalBookArtifact(
    record.coverStoragePath,
    canonicalPaths.cover,
    "Cover"
  );
  const pdfStoragePath = assertCanonicalBookArtifact(
    record.pdfStoragePath,
    canonicalPaths.interior,
    "Interior"
  );
  const updates = {};
  const coverArtifact = await mintPermanentDownloadArtifact(bucket, coverStoragePath, "Cover");
  const pdfArtifact = await mintPermanentDownloadArtifact(bucket, pdfStoragePath, "Interior");
  if (!coverArtifact || !pdfArtifact) {
    return {
      ...record,
      coverURL: null,
      pdfURL: null
    };
  }
  if (record.coverURL !== coverArtifact.url) {
    updates.coverURL = coverArtifact.url;
  }
  if (record.pdfURL !== pdfArtifact.url) {
    updates.pdfURL = pdfArtifact.url;
  }
  if (Object.keys(updates).length > 0) {
    updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await docRef.set(updates, { merge: true });
  }
  return {
    ...record,
    ...updates,
    coverURL: coverArtifact.url,
    pdfURL: pdfArtifact.url,
    coverArtifactGeneration: coverArtifact.generation,
    coverArtifactSize: coverArtifact.size,
    pdfArtifactGeneration: pdfArtifact.generation,
    pdfArtifactSize: pdfArtifact.size
  };
}

function checkoutFulfillmentFingerprint(record, selectedPodPackageId) {
  const value = record && typeof record === "object" ? record : {};
  const payload = {
    renderStatus: String(value.renderStatus || ""),
    pageCount: Number(value.pageCount || value.pages?.length || 0),
    pageWidth: Number(value.pageWidth || 0),
    pageHeight: Number(value.pageHeight || 0),
    orientation: String(value.orientation || ""),
    layoutVersion: String(value.layoutVersion || ""),
    trimWidth: Number(value.trimSizeInches?.width || 0),
    trimHeight: Number(value.trimSizeInches?.height || 0),
    coverStoragePath: String(value.coverStoragePath || ""),
    pdfStoragePath: String(value.pdfStoragePath || ""),
    coverArtifactGeneration: String(value.coverArtifactGeneration || ""),
    coverArtifactSize: Number(value.coverArtifactSize || 0),
    pdfArtifactGeneration: String(value.pdfArtifactGeneration || ""),
    pdfArtifactSize: Number(value.pdfArtifactSize || 0),
    selectedPodPackageId: String(selectedPodPackageId || "")
  };
  return crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex");
}

async function validateCheckoutBookArtifacts({ userId, expectedItems, ensureArtifacts }) {
  if (!Array.isArray(expectedItems) || expectedItems.length === 0 || expectedItems.length > 100) {
    throw new Error("Checkout book list is invalid");
  }
  const recordsByBook = new Map();
  const validatedItems = [];
  for (const item of expectedItems) {
    const bookVersionId = String(item?.bookVersionId || "").trim();
    if (!bookVersionId || !item?.fulfillmentFingerprint) {
      throw new Error("Checkout fulfillment fingerprint is missing");
    }
    let record = recordsByBook.get(bookVersionId);
    if (!record) {
      record = await ensureArtifacts(userId, bookVersionId);
      recordsByBook.set(bookVersionId, record);
    }
    if (!record || record.renderStatus !== "rendered" || !record.coverURL || !record.pdfURL) {
      throw new Error("Checkout book artifacts are unavailable");
    }
    const currentFingerprint = checkoutFulfillmentFingerprint(
      record,
      item.selectedPodPackageId
    );
    if (currentFingerprint !== item.fulfillmentFingerprint) {
      throw new Error("Checkout book changed after pricing");
    }
    validatedItems.push({ item, record });
  }
  return validatedItems;
}

module.exports = {
  canonicalBookArtifactPaths,
  assertCanonicalBookArtifact,
  assertPdfMetadata,
  checkoutFulfillmentFingerprint,
  mintPermanentDownloadUrl,
  ensureBookVersionArtifactUrls,
  validateCheckoutBookArtifacts
};
