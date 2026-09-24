const crypto = require("crypto");

const GUEST_RECOVERY_PROTOCOL_VERSION = 1;
const GUEST_RECOVERY_COLLECTION = "guestRecoveryMappings";
const GUEST_CONTENT_COLLECTIONS = [
  "memories",
  "profiles",
  "bookVersions",
  "storybookJobs",
  "orders",
  "pendingCartCheckouts"
];

function isRecoverableGuestToken(token) {
  if (token?.memoirGuest === true) return true;

  const identities = token?.firebase?.identities;
  const hasLinkedIdentity = identities && Object.keys(identities).some((provider) => {
    const values = identities[provider];
    return Array.isArray(values) ? values.length > 0 : Boolean(values);
  });
  const provider = token?.firebase?.sign_in_provider || token?.sign_in_provider;
  return !hasLinkedIdentity && provider === "anonymous";
}

function normalizedRecoveryRequest(data, HttpsError) {
  const protocolVersion = Number(data?.protocolVersion);
  if (protocolVersion !== GUEST_RECOVERY_PROTOCOL_VERSION) {
    throw new HttpsError("invalid-argument", "Unsupported guest recovery protocol version.");
  }

  const recoverySecret = typeof data?.recoverySecret === "string"
    ? data.recoverySecret.trim()
    : "";
  if (!/^[A-Za-z0-9+/]{43}=$/.test(recoverySecret)) {
    throw new HttpsError("invalid-argument", "Recovery secret must be 32-byte base64.");
  }
  const decoded = Buffer.from(recoverySecret, "base64");
  if (decoded.length !== 32 || decoded.toString("base64") !== recoverySecret) {
    throw new HttpsError("invalid-argument", "Recovery secret must be 32-byte base64.");
  }

  return {
    protocolVersion,
    secretHash: crypto.createHash("sha256").update(decoded).digest("hex")
  };
}

function assertAuthenticated(request, HttpsError) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
}

function assertRecoverableGuest(request, HttpsError) {
  assertAuthenticated(request, HttpsError);
  if (!isRecoverableGuestToken(request.auth.token)) {
    throw new HttpsError("failed-precondition", "Guest recovery requires a guest session.");
  }
}

async function deletionMarkerExists(db, userId) {
  const snapshot = await db.collection("accountDeletionRequests").doc(userId).get();
  return snapshot.exists;
}

async function guestAccountHasContent(db, guestUid) {
  const userRef = db.collection("users").doc(guestUid);
  const snapshots = await Promise.all(GUEST_CONTENT_COLLECTIONS.map((collectionName) => (
    userRef.collection(collectionName).limit(1).get()
  )));
  if (snapshots.some((snapshot) => !snapshot.empty)) return true;

  const pendingSingleCheckouts = await db.collection("pendingSingleCheckouts")
    .where("userId", "==", guestUid)
    .limit(1)
    .get();
  return !pendingSingleCheckouts.empty;
}

function createEnrollGuestRecoveryHandler({ db, serverTimestamp, HttpsError }) {
  return async (request) => {
    assertRecoverableGuest(request, HttpsError);
    const { protocolVersion, secretHash } = normalizedRecoveryRequest(request.data, HttpsError);
    const guestUid = request.auth.uid;
    const mappingRef = db.collection(GUEST_RECOVERY_COLLECTION).doc(secretHash);
    const deletionRef = db.collection("accountDeletionRequests").doc(guestUid);

    await db.runTransaction(async (transaction) => {
      const [mapping, deletion] = await Promise.all([
        transaction.get(mappingRef),
        transaction.get(deletionRef)
      ]);
      if (deletion.exists) {
        throw new HttpsError("failed-precondition", "This account cannot be recovered.");
      }
      if (mapping.exists && mapping.data()?.guestUid !== guestUid) {
        throw new HttpsError("already-exists", "This recovery secret is already enrolled.");
      }

      const fields = {
        guestUid,
        protocolVersion,
        status: "active",
        updatedAt: serverTimestamp()
      };
      if (!mapping.exists) fields.createdAt = serverTimestamp();
      transaction.set(mappingRef, fields, { merge: true });
    });

    return { status: "active" };
  };
}

async function assertTargetRemainsRecoverableGuest(auth, guestUid, HttpsError) {
  try {
    const user = await auth.getUser(guestUid);
    const providers = Array.isArray(user.providerData) ? user.providerData : [];
    if (providers.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        "This recovery record belongs to a linked account. Sign in normally."
      );
    }
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error?.code !== "auth/user-not-found") throw error;
    // Firebase may automatically clean up an old anonymous Auth record. A
    // custom-token sign-in recreates the same UID without moving user data.
  }
}

function createRecoverGuestAccountHandler({
  db,
  auth,
  serverTimestamp,
  HttpsError,
  requesterHasContent = (guestUid) => guestAccountHasContent(db, guestUid)
}) {
  return async (request) => {
    assertRecoverableGuest(request, HttpsError);
    const { secretHash } = normalizedRecoveryRequest(request.data, HttpsError);
    const requesterUid = request.auth.uid;
    const mappingRef = db.collection(GUEST_RECOVERY_COLLECTION).doc(secretHash);
    const mapping = await mappingRef.get();
    if (!mapping.exists || mapping.data()?.status !== "active") {
      throw new HttpsError("not-found", "No active guest recovery record was found.");
    }

    const guestUid = String(mapping.data()?.guestUid || "").trim();
    if (!guestUid) {
      throw new HttpsError("failed-precondition", "Guest recovery record is invalid.");
    }
    const [sourceDeleted, requesterDeleted] = await Promise.all([
      deletionMarkerExists(db, guestUid),
      deletionMarkerExists(db, requesterUid)
    ]);
    if (sourceDeleted || requesterDeleted) {
      throw new HttpsError("failed-precondition", "This account cannot be recovered.");
    }
    if (guestUid !== requesterUid && await requesterHasContent(requesterUid)) {
      throw new HttpsError(
        "failed-precondition",
        "Guest recovery cannot replace an account that already contains data."
      );
    }

    await assertTargetRemainsRecoverableGuest(auth, guestUid, HttpsError);
    const customToken = await auth.createCustomToken(guestUid, { memoirGuest: true });
    await mappingRef.set({
      lastRecoveredAt: serverTimestamp(),
      updatedAt: serverTimestamp()
    }, { merge: true });

    return { customToken };
  };
}

async function revokeGuestRecoveryMappings({ db, guestUid, serverTimestamp }) {
  const snapshot = await db.collection(GUEST_RECOVERY_COLLECTION)
    .where("guestUid", "==", guestUid)
    .get();
  if (snapshot.empty) return 0;

  let batch = db.batch();
  let pending = 0;
  let revoked = 0;
  for (const document of snapshot.docs) {
    batch.set(document.ref, {
      status: "revoked",
      revokedAt: serverTimestamp(),
      updatedAt: serverTimestamp()
    }, { merge: true });
    pending += 1;
    revoked += 1;
    if (pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  return revoked;
}

function createRevokeGuestRecoveryHandler({ db, serverTimestamp, HttpsError }) {
  return async (request) => {
    assertAuthenticated(request, HttpsError);
    await revokeGuestRecoveryMappings({
      db,
      guestUid: request.auth.uid,
      serverTimestamp
    });
    return { status: "revoked" };
  };
}

module.exports = {
  GUEST_RECOVERY_COLLECTION,
  GUEST_RECOVERY_PROTOCOL_VERSION,
  createEnrollGuestRecoveryHandler,
  createRecoverGuestAccountHandler,
  createRevokeGuestRecoveryHandler,
  guestAccountHasContent,
  isRecoverableGuestToken,
  normalizedRecoveryRequest,
  revokeGuestRecoveryMappings
};
