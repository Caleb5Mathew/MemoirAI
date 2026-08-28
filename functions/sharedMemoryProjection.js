"use strict";

function sharedMemoryProjection(memoryId, data, serverTimestamp) {
  if (!memoryId || typeof serverTimestamp !== "function") {
    throw new Error("Shared memory projection dependencies are required");
  }
  const source = data && typeof data === "object" ? data : {};
  const projection = {
    memoryId,
    updatedAt: serverTimestamp()
  };
  for (const key of ["prompt", "transcription", "profileName", "createdAt", "audioStoragePath"]) {
    if (source[key] != null) projection[key] = source[key];
  }
  return projection;
}

function createSharedMemoryProjectionHandler({ db, serverTimestamp }) {
  return async (event) => {
    const ownerId = event.params.userId;
    const memoryId = event.params.memoryId;
    const target = db.collection("users").doc(ownerId)
      .collection("sharedMemories").doc(memoryId);
    const after = event.data?.after;
    if (!after?.exists) {
      await target.delete();
      return;
    }
    await target.set(sharedMemoryProjection(memoryId, after.data(), serverTimestamp), { merge: false });
  };
}

module.exports = {
  createSharedMemoryProjectionHandler,
  sharedMemoryProjection
};
