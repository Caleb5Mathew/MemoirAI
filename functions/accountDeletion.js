const crypto = require("crypto");
const { memoryIndexBelongsToUser } = require("./memoryIndexOwnership");
const { beginAccountDeletion } = require("./accountOperationLock");

const RETAINED_SUBCOLLECTIONS = new Set(["orders", "paidBookCheckouts"]);
const SHARING_SUBCOLLECTIONS = ["sharedAudioAccess", "accessGrants"];
const STORAGE_DELETE_ATTEMPTS = 3;
const MAX_RECENT_AUTH_AGE_SECONDS = 5 * 60;
const TERMINAL_CHECKOUT_STATUSES = new Set([
  "paid",
  "checkout_expired",
  "expired",
  "cancelled",
  "canceled",
  "stripe_create_failed",
  "failed"
]);

function blockingPendingCheckoutIds(documents) {
  return documents
    .filter((document) => {
      const status = String(document.data()?.status || "").trim().toLowerCase();
      return !TERMINAL_CHECKOUT_STATUSES.has(status);
    })
    .map((document) => document.id);
}

async function findBlockingPendingCheckouts(db, userId) {
  const userRef = db.collection("users").doc(userId);
  const [cartSnapshot, singleSnapshot] = await Promise.all([
    userRef.collection("pendingCartCheckouts").get(),
    db.collection("pendingSingleCheckouts").where("userId", "==", userId).get()
  ]);
  return [
    ...blockingPendingCheckoutIds(cartSnapshot.docs),
    ...blockingPendingCheckoutIds(singleSnapshot.docs)
  ];
}

function isAnonymousToken(token) {
  const identities = token?.firebase?.identities;
  const hasLinkedIdentity = identities && Object.keys(identities).some((provider) => {
    const values = identities[provider];
    return Array.isArray(values) ? values.length > 0 : Boolean(values);
  });
  return !hasLinkedIdentity && (token?.firebase?.sign_in_provider === "anonymous"
    || token?.sign_in_provider === "anonymous");
}

function assertRecentAuthentication(request, nowSeconds, HttpsError) {
  const token = request.auth?.token || {};
  if (isAnonymousToken(token)) return;

  const authenticatedAt = Number(token.auth_time);
  const age = nowSeconds() - authenticatedAt;
  if (!Number.isFinite(authenticatedAt) || authenticatedAt <= 0
      || !Number.isFinite(age) || age < 0 || age > MAX_RECENT_AUTH_AGE_SECONDS) {
    throw new HttpsError(
      "failed-precondition",
      "For your security, sign in again before deleting your account.",
      { reason: "requires-recent-login" }
    );
  }
}

function retainedOrderArtifactPaths(orderDocuments, userId) {
  const prefix = `users/${userId}/bookVersions/`;
  const retained = new Set();
  for (const order of orderDocuments) {
    const data = typeof order?.data === "function" ? order.data() : order;
    for (const field of ["coverPdfStoragePath", "interiorPdfStoragePath"]) {
      const path = String(data?.[field] || "").trim();
      if (path.startsWith(prefix) && path.toLowerCase().endsWith(".pdf")) {
        retained.add(path);
      }
    }
  }
  return retained;
}

async function deleteMemoryIndexes(db, memoriesRef) {
  let batch = db.batch();
  let pending = 0;
  for await (const memory of memoriesRef.stream()) {
    const indexRef = db.collection("memoryIndex").doc(memory.id);
    const indexSnapshot = await indexRef.get();
    if (!memoryIndexBelongsToUser(indexSnapshot, memoriesRef.parent.id)) {
      continue;
    }
    batch.delete(indexRef);
    pending += 1;
    if (pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) {
    await batch.commit();
  }
}

async function deleteStorageFileSecurely(file) {
  let lastError;
  for (let attempt = 0; attempt < STORAGE_DELETE_ATTEMPTS; attempt += 1) {
    try {
      await file.delete();
      return;
    } catch (error) {
      if (Number(error?.code || 0) === 404) return;
      lastError = error;
    }
  }

  // Firebase download-token URLs bypass Storage Rules. Revoke that bearer
  // token before surfacing the deletion failure so a retry remains private.
  await file.setMetadata({
    metadata: { firebaseStorageDownloadTokens: null }
  });
  throw lastError;
}

async function deleteStorageFiles(files) {
  for (let offset = 0; offset < files.length; offset += 20) {
    await Promise.all(files.slice(offset, offset + 20).map(deleteStorageFileSecurely));
  }
}

async function revokeAccountSharing(db, userRef) {
  const results = await Promise.allSettled(SHARING_SUBCOLLECTIONS.map((collectionName) => (
    db.recursiveDelete(userRef.collection(collectionName))
  )));
  const failure = results.find((result) => result.status === "rejected");
  if (failure) {
    throw failure.reason;
  }
}

async function deleteAccountAudioStorage(bucket, userId) {
  const [files] = await bucket.getFiles({ prefix: `users/${userId}/audio/` });
  await deleteStorageFiles(files);
}

async function deleteUnretainedStorage(bucket, userId, retainedPaths) {
  const [files] = await bucket.getFiles({ prefix: `users/${userId}/` });
  const deletions = files.filter((file) => !retainedPaths.has(file.name));
  await deleteStorageFiles(deletions);
}

async function deleteAuthUserIfPresent(auth, userId) {
  try {
    await auth.deleteUser(userId);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
  }
}

function createDeleteOwnAccountHandler({
  db,
  bucket,
  auth,
  serverTimestamp,
  HttpsError,
  nowSeconds = () => Math.floor(Date.now() / 1000)
}) {
  return async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const userId = request.auth.uid;
    const markerRef = db.collection("accountDeletionRequests").doc(userId);
    const markerSnapshot = await markerRef.get();
    const marker = markerSnapshot.exists ? markerSnapshot.data() : null;
    if (marker?.status === "complete") {
      return {
        status: "complete",
        retainedOrderRecords: Number(marker.retainedOrderCount || 0)
      };
    }
    if (marker?.status === "deleting_auth") {
      try {
        await deleteAuthUserIfPresent(auth, userId);
        await markerRef.set({
          status: "complete",
          completedAt: serverTimestamp(),
          updatedAt: serverTimestamp()
        }, { merge: true });
        return {
          status: "complete",
          retainedOrderRecords: Number(marker.retainedOrderCount || 0)
        };
      } catch (error) {
        console.error("deleteOwnAccount auth cleanup retry failed", userId, String(error?.message || error));
        throw new HttpsError(
          "internal",
          "We could not finish deleting your account. Please try again."
        );
      }
    }

    assertRecentAuthentication(request, nowSeconds, HttpsError);

    const blockingCheckouts = await findBlockingPendingCheckouts(db, userId);
    if (blockingCheckouts.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        "Finish or cancel your open book checkout before deleting your account.",
        { reason: "active-checkout" }
      );
    }

    const userRef = db.collection("users").doc(userId);
    const deletionFields = {
      status: "deleting",
      updatedAt: serverTimestamp()
    };
    await beginAccountDeletion({
      db,
      userId,
      HttpsError,
      deletionFields,
      serverTimestamp
    });

    let authDeletionStarted = false;
    try {
      // Disable both grant-based and byte-level shared-audio access before the
      // slower Firestore cleanup. Attempt both even if either operation fails.
      const accessResults = await Promise.allSettled([
        revokeAccountSharing(db, userRef),
        deleteAccountAudioStorage(bucket, userId)
      ]);
      const accessFailure = accessResults.find((result) => result.status === "rejected");
      if (accessFailure) throw accessFailure.reason;

      const memoriesRef = userRef.collection("memories");
      await deleteMemoryIndexes(db, memoriesRef);

      const ordersSnapshot = await userRef.collection("orders").get();
      const retainedPaths = retainedOrderArtifactPaths(ordersSnapshot.docs, userId);

      const subcollections = await userRef.listCollections();
      for (const collection of subcollections) {
        if (!RETAINED_SUBCOLLECTIONS.has(collection.id)) {
          await db.recursiveDelete(collection);
        }
      }
      await userRef.delete();
      await deleteUnretainedStorage(bucket, userId, retainedPaths);

      const completionFields = {
        retainedOrderCount: ordersSnapshot.size,
        retainedArtifactCount: retainedPaths.size,
        userHash: crypto.createHash("sha256").update(userId).digest("hex")
      };
      await markerRef.set({
        status: "deleting_auth",
        updatedAt: serverTimestamp(),
        ...completionFields
      }, { merge: true });

      authDeletionStarted = true;
      await deleteAuthUserIfPresent(auth, userId);

      await markerRef.set({
        status: "complete",
        completedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        ...completionFields
      }, { merge: true }).catch((error) => {
        console.error("deleteOwnAccount completion marker failed", userId, String(error?.message || error));
      });

      return {
        status: "complete",
        retainedOrderRecords: ordersSnapshot.size
      };
    } catch (error) {
      const failureFields = {
        updatedAt: serverTimestamp(),
        failureCode: String(error?.code || "unknown").slice(0, 80)
      };
      // Auth deletion can succeed even when its network response is lost. Keep
      // this resumable stage instead of downgrading it to a recent-auth retry.
      failureFields.status = authDeletionStarted ? "deleting_auth" : "failed";
      await markerRef.set(failureFields, { merge: true }).catch(() => {});
      console.error("deleteOwnAccount failed", userId, String(error?.message || error));
      throw new HttpsError(
        "internal",
        "We could not finish deleting your account. Please try again."
      );
    }
  };
}

module.exports = {
  MAX_RECENT_AUTH_AGE_SECONDS,
  assertRecentAuthentication,
  blockingPendingCheckoutIds,
  createDeleteOwnAccountHandler,
  deleteAccountAudioStorage,
  deleteMemoryIndexes,
  deleteStorageFileSecurely,
  deleteStorageFiles,
  deleteUnretainedStorage,
  findBlockingPendingCheckouts,
  revokeAccountSharing,
  retainedOrderArtifactPaths
};
