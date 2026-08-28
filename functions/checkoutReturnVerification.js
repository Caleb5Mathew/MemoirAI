const { HttpsError } = require("firebase-functions/v2/https");

const STRIPE_CHECKOUT_SESSION_ID_PATTERN = /^cs_(?:test|live)_[A-Za-z0-9]{8,200}$/;

function normalizeCheckoutSessionId(raw) {
  if (typeof raw !== "string") return null;
  const value = raw.trim();
  return STRIPE_CHECKOUT_SESSION_ID_PATTERN.test(value) ? value : null;
}

function checkoutSessionBelongsToUser(session, userId) {
  const metadataUserId = String(session?.metadata?.userId || "");
  return Boolean(userId) && metadataUserId === userId;
}

function checkoutSessionHasConfirmedPayment(session) {
  return session?.status === "complete" &&
    (session?.payment_status === "paid" || session?.payment_status === "no_payment_required");
}

function createVerifyCheckoutReturnHandler({ createStripeClient, orderRecordExists }) {
  if (typeof createStripeClient !== "function") {
    throw new TypeError("createStripeClient is required");
  }
  if (typeof orderRecordExists !== "function") {
    throw new TypeError("orderRecordExists is required");
  }

  return async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const sessionId = normalizeCheckoutSessionId(request.data?.sessionId);
    if (!sessionId) {
      throw new HttpsError("invalid-argument", "Invalid checkout session");
    }

    let session;
    try {
      session = await createStripeClient().checkout.sessions.retrieve(sessionId);
    } catch (error) {
      const stripeStatus = Number(error?.statusCode || error?.status || 0);
      if (stripeStatus === 404 || error?.code === "resource_missing") {
        throw new HttpsError("not-found", "Checkout session not found");
      }
      console.error("verifyCheckoutReturn Stripe lookup failed", {
        type: String(error?.type || ""),
        code: String(error?.code || "")
      });
      throw new HttpsError("unavailable", "Could not verify payment. Try again shortly.");
    }

    if (!checkoutSessionBelongsToUser(session, request.auth.uid)) {
      throw new HttpsError("permission-denied", "Checkout session does not belong to this account");
    }

    const paymentConfirmed = checkoutSessionHasConfirmedPayment(session);
    const orderRecorded = paymentConfirmed
      ? await orderRecordExists(request.auth.uid, sessionId)
      : false;
    return {
      verified: paymentConfirmed && orderRecorded,
      paymentConfirmed,
      orderRecorded,
      sessionId,
      checkoutStatus: String(session.status || "unknown"),
      paymentStatus: String(session.payment_status || "unknown")
    };
  };
}

module.exports = {
  normalizeCheckoutSessionId,
  checkoutSessionBelongsToUser,
  checkoutSessionHasConfirmedPayment,
  createVerifyCheckoutReturnHandler
};
