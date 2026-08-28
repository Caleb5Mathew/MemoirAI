const DEFAULT_CHECKOUT_LEASE_MILLIS = 35 * 60 * 1000;

function lockRef(db, userId) {
  return db.collection("accountOperationLocks").doc(userId);
}

function deletionRef(db, userId) {
  return db.collection("accountDeletionRequests").doc(userId);
}

function activeStorybookRef(db, userId) {
  return db.collection("users").doc(userId).collection("aiUsage").doc("storybook_active");
}

function isActiveCheckoutLock(data, nowMillis) {
  return data?.state === "checkout"
    && Number(data.checkoutExpiresAtMillis || 0) > nowMillis;
}

function isActiveStorybookLease(data, nowMillis) {
  const expiresAt = data?.leaseExpiresAt?.toMillis?.()
    ?? data?.leaseExpiresAt?.toDate?.()?.getTime?.()
    ?? 0;
  return typeof data?.jobId === "string"
    && data.jobId.length > 0
    && Number(expiresAt) > nowMillis;
}

async function acquireCheckoutLease({
  db,
  userId,
  leaseId,
  HttpsError,
  nowMillis = () => Date.now(),
  leaseMillis = DEFAULT_CHECKOUT_LEASE_MILLIS,
  serverTimestamp
}) {
  const operationRef = lockRef(db, userId);
  const accountDeletionRef = deletionRef(db, userId);
  await db.runTransaction(async (transaction) => {
    const [deletionSnapshot, operationSnapshot] = await Promise.all([
      transaction.get(accountDeletionRef),
      transaction.get(operationRef)
    ]);
    if (deletionSnapshot.exists) {
      throw new HttpsError(
        "failed-precondition",
        "This account is being deleted and cannot start a new checkout."
      );
    }

    const now = nowMillis();
    const operation = operationSnapshot.exists ? operationSnapshot.data() : null;
    if (isActiveCheckoutLock(operation, now) && operation.checkoutLeaseId !== leaseId) {
      throw new HttpsError(
        "failed-precondition",
        "Another book checkout is already open for this account.",
        { reason: "active-checkout" }
      );
    }
    if (operation?.state === "deleting") {
      throw new HttpsError(
        "failed-precondition",
        "This account is being deleted and cannot start a new checkout."
      );
    }

    transaction.set(operationRef, {
      state: "checkout",
      checkoutLeaseId: leaseId,
      checkoutExpiresAtMillis: now + leaseMillis,
      updatedAt: serverTimestamp()
    });
  });
}

async function beginAccountDeletion({
  db,
  userId,
  HttpsError,
  deletionFields,
  nowMillis = () => Date.now(),
  serverTimestamp
}) {
  const operationRef = lockRef(db, userId);
  const accountDeletionRef = deletionRef(db, userId);
  const storybookRef = activeStorybookRef(db, userId);
  await db.runTransaction(async (transaction) => {
    const [deletionSnapshot, operationSnapshot, storybookSnapshot] = await Promise.all([
      transaction.get(accountDeletionRef),
      transaction.get(operationRef),
      transaction.get(storybookRef)
    ]);
    const operation = operationSnapshot.exists ? operationSnapshot.data() : null;
    if (isActiveCheckoutLock(operation, nowMillis())) {
      throw new HttpsError(
        "failed-precondition",
        "Finish or cancel your open book checkout before deleting your account.",
        { reason: "active-checkout" }
      );
    }
    if (storybookSnapshot.exists
        && isActiveStorybookLease(storybookSnapshot.data(), nowMillis())) {
      throw new HttpsError(
        "failed-precondition",
        "Wait for your storybook to finish before deleting your account.",
        { reason: "active-storybook" }
      );
    }

    const fields = { ...deletionFields };
    if (!deletionSnapshot.exists) fields.requestedAt = serverTimestamp();
    transaction.set(accountDeletionRef, fields, { merge: true });
    transaction.set(operationRef, {
      state: "deleting",
      checkoutLeaseId: null,
      checkoutExpiresAtMillis: 0,
      updatedAt: serverTimestamp()
    });
  });
}

async function releaseCheckoutLease({ db, userId, leaseId }) {
  if (!userId || !leaseId) return false;
  const operationRef = lockRef(db, userId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(operationRef);
    const operation = snapshot.exists ? snapshot.data() : null;
    if (operation?.state !== "checkout" || operation.checkoutLeaseId !== leaseId) {
      return false;
    }
    transaction.delete(operationRef);
    return true;
  });
}

module.exports = {
  DEFAULT_CHECKOUT_LEASE_MILLIS,
  acquireCheckoutLease,
  beginAccountDeletion,
  isActiveCheckoutLock,
  isActiveStorybookLease,
  releaseCheckoutLease
};
