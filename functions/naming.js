/**
 * User handles (caleb_mathew1), global book/memory sequence numbers, and display names.
 * Used by Firestore triggers in index.js.
 */

const admin = require("firebase-admin");

/**
 * @param {string} raw
 * @returns {string}
 */
function slugifyName(raw) {
  const s = String(raw || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .replace(/_+/g, "_");
  const trimmed = s.slice(0, 48).replace(/^_+|_+$/g, "");
  return trimmed || "user";
}

/**
 * @param {string} userHandle
 * @param {number} seq
 */
function bookDisplayNameFor(userHandle, seq) {
  return `${userHandle}_book${seq}`;
}

/**
 * @param {string} userHandle
 * @param {number} seq
 */
function memoryDisplayNameFor(userHandle, seq) {
  return `${userHandle}_memory${seq}`;
}

/**
 * Monotonic global counter under `counters/{counterDocId}` (field `next`).
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} counterDocId e.g. globalBooks, globalMemories
 * @returns {Promise<number>} allocated sequence (1-based)
 */
async function allocateGlobalCounter(db, counterDocId) {
  const ref = db.collection("counters").doc(counterDocId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prev =
      snap.exists && Number.isFinite(Number(snap.data().next)) ? Number(snap.data().next) : 0;
    const allocated = prev + 1;
    tx.set(
      ref,
      {
        next: allocated,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );
    return allocated;
  });
}

/**
 * Allocates `userHandle` = `{slug}{n}` and writes it to `users/{uid}` if missing.
 * Uses transaction on `userHandles/{slug}` for per-slug suffix and `users/{uid}` for idempotency.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @returns {Promise<string>}
 */
async function ensureUserHandleAllocated(db, uid) {
  const userRef = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const d = userSnap.exists ? userSnap.data() || {} : {};
    const existing = d.userHandle != null ? String(d.userHandle).trim() : "";
    if (existing) {
      return existing;
    }
    const raw =
      [d.profileName, d.displayName, d.email, "user"].map((x) => String(x || "").trim()).find(Boolean) || "user";
    const slug = slugifyName(raw);
    const seqRef = db.collection("userHandles").doc(slug);
    const seqSnap = await tx.get(seqRef);
    const prev =
      seqSnap.exists && Number.isFinite(Number(seqSnap.data().next))
        ? Number(seqSnap.data().next)
        : 0;
    const num = prev + 1;
    tx.set(
      seqRef,
      {
        next: num,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );
    const handle = `${slug}${num}`;
    tx.set(
      userRef,
      {
        userHandle: handle,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );
    return handle;
  });
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @returns {Promise<string>}
 */
async function resolveUserHandleForNaming(db, uid) {
  const snap = await db.collection("users").doc(uid).get();
  const h = snap.exists ? String(snap.data().userHandle || "").trim() : "";
  if (h) return h;
  return ensureUserHandleAllocated(db, uid);
}

module.exports = {
  slugifyName,
  bookDisplayNameFor,
  memoryDisplayNameFor,
  allocateGlobalCounter,
  ensureUserHandleAllocated,
  resolveUserHandleForNaming
};
