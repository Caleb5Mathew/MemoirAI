"use strict";

const crypto = require("crypto");

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function canonicalSharedAudioFile(ownerId, memoryId, storagePath) {
  if (!ownerId || !UUID_PATTERN.test(String(memoryId || ""))) return null;
  for (const extension of ["m4a", "caf"]) {
    const audioFile = `${memoryId}.${extension}`;
    if (storagePath === `users/${ownerId}/audio/${audioFile}`) return audioFile;
  }
  return null;
}

function firebaseDownloadURL(bucketName, storagePath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucketName)}`
    + `/o/${encodeURIComponent(storagePath)}?alt=media&token=${encodeURIComponent(token)}`;
}

function createRevokeSharedMemoryAccessHandler({
  db,
  bucket,
  HttpsError,
  serverTimestamp,
  randomUUID = crypto.randomUUID
}) {
  return async (request) => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Must be signed in");
    const ownerId = request.auth.uid;
    const grantId = String(request.data?.grantId || "").trim();
    const requestedMemoryId = String(request.data?.memoryId || "").trim();
    if (!grantId || grantId.length > 300 || grantId.includes("/")
        || (requestedMemoryId && !UUID_PATTERN.test(requestedMemoryId))) {
      throw new HttpsError("invalid-argument", "Invalid sharing grant");
    }

    const userRef = db.collection("users").doc(ownerId);
    const grantRef = userRef.collection("accessGrants").doc(grantId);
    const grantSnapshot = await grantRef.get();
    if (!grantSnapshot.exists) {
      throw new HttpsError("not-found", "Sharing grant not found");
    }
    const grant = grantSnapshot.data() || {};
    if (typeof grant.requesterUid !== "string") {
      throw new HttpsError("failed-precondition", "Sharing grant does not match this memory");
    }
    let memoryId = String(grant.memoryId || "");
    if (!memoryId) {
      const legacyRequestSnapshot = await userRef.collection("accessRequests").doc(grantId).get();
      const legacyRequest = legacyRequestSnapshot.data() || {};
      if (!legacyRequestSnapshot.exists
          || legacyRequest.requesterUid !== grant.requesterUid
          || legacyRequest.status !== "approved") {
        throw new HttpsError("failed-precondition", "Legacy sharing request is unavailable");
      }
      memoryId = String(legacyRequest.memoryId || "");
    }
    if (!UUID_PATTERN.test(memoryId) || (requestedMemoryId && requestedMemoryId !== memoryId)) {
      throw new HttpsError("failed-precondition", "Sharing grant does not match this memory");
    }
    const memoryRef = userRef.collection("memories").doc(memoryId);
    const memorySnapshot = await memoryRef.get();
    const audioFile = canonicalSharedAudioFile(
      ownerId,
      memoryId,
      memorySnapshot.data()?.audioStoragePath
    );

    let replacementAudioURL = null;
    if (audioFile) {
      const storagePath = `users/${ownerId}/audio/${audioFile}`;
      const file = bucket.file(storagePath);
      const [exists] = await file.exists();
      if (exists) {
        const [metadata] = await file.getMetadata();
        const replacementToken = randomUUID();
        await file.setMetadata({
          metadata: {
            ...(metadata.metadata || {}),
            firebaseStorageDownloadTokens: replacementToken
          }
        });
        replacementAudioURL = firebaseDownloadURL(bucket.name, storagePath, replacementToken);
      }
    }

    const batch = db.batch();
    batch.delete(grantRef);
    if (audioFile) {
      batch.delete(userRef.collection("sharedAudioAccess").doc(`${audioFile}__${grant.requesterUid}`));
    }
    if (replacementAudioURL) {
      batch.set(memoryRef, { audioURL: replacementAudioURL }, { merge: true });
    }
    batch.set(userRef.collection("accessRequests").doc(grantId), {
      status: "denied",
      respondedAt: serverTimestamp()
    }, { merge: true });
    await batch.commit();
    return { status: "revoked" };
  };
}

module.exports = {
  canonicalSharedAudioFile,
  firebaseDownloadURL,
  createRevokeSharedMemoryAccessHandler
};
