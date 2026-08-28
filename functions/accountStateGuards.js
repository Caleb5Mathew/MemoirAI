async function assertAccountAvailableForCheckout(db, userId, HttpsError) {
  const marker = await db.collection("accountDeletionRequests").doc(userId).get();
  if (marker.exists) {
    throw new HttpsError(
      "failed-precondition",
      "This account is being deleted and cannot start a new checkout."
    );
  }
}

async function assertAccountNotDeleting(db, userId) {
  const marker = await db.collection("accountDeletionRequests").doc(userId).get();
  if (marker.exists) {
    const error = new Error("Account deletion is in progress");
    error.accountDeletionRequested = true;
    error.permanent = true;
    throw error;
  }
}

module.exports = { assertAccountAvailableForCheckout, assertAccountNotDeleting };
