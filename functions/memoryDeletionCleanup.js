const { memoryIndexBelongsToUser } = require("./memoryIndexOwnership");

function createMemoryDeletionCleanupHandler({ db, bucket, serverTimestamp }) {
  return async (event) => {
    const { userId, memoryId } = event.params;
    try {
      const userRef = db.collection("users").doc(userId);
      const accountDeletion = await db.collection("accountDeletionRequests").doc(userId).get();
      const memoryIndexRef = db.collection("memoryIndex").doc(memoryId);
      const memoryIndex = await memoryIndexRef.get();
      const batch = db.batch();
      if (!accountDeletion.exists) {
        batch.set(userRef.collection("memoryTombstones").doc(memoryId), {
          deletedAt: serverTimestamp(),
          schemaVersion: 1
        }, { merge: true });
        for (const extension of ["m4a", "caf"]) {
          batch.set(userRef.collection("memoryAudioTombstones").doc(`${memoryId}.${extension}`), {
            deletedAt: serverTimestamp(),
            schemaVersion: 1
          }, { merge: true });
        }
      }
      if (memoryIndexBelongsToUser(memoryIndex, userId)) {
        batch.delete(memoryIndexRef);
      }
      batch.delete(userRef.collection("memories").doc(memoryId));
      await batch.commit();

      await Promise.all(["m4a", "caf"].map(async (extension) => {
        try {
          await bucket.file(`users/${userId}/audio/${memoryId}.${extension}`).delete();
        } catch (error) {
          if (Number(error?.code || 0) !== 404) throw error;
        }
      }));
    } catch (error) {
      console.error("memory tombstone cleanup failed", memoryId, String(error?.message || error));
      throw error;
    }
  };
}

module.exports = { createMemoryDeletionCleanupHandler };
