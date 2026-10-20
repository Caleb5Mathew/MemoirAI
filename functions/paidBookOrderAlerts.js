"use strict";

const { randomUUID } = require("node:crypto");

const BOOK_ORDER_RECIPIENTS = Object.freeze([
  "caleb5mathew@gmail.com",
  "calebmathew2121@gmail.com"
]);
const DELIVERY_LEASE_MS = 5 * 60 * 1000;

function paidBookOrderAlert(data, userId) {
  if (!data || data.isTestOrder !== false || data.userId !== userId ||
      typeof data.stripeSessionId !== "string" || !data.stripeSessionId.trim() ||
      !data.paidAt || !Array.isArray(data.orderIds) || !data.orderIds.length ||
      data.orderIds.some((id) => typeof id !== "string" || !id.trim()) ||
      !Array.isArray(data.items) || !data.items.length) return null;
  const quantities = data.items.map((item) => item?.quantity);
  if (quantities.some((quantity) => !Number.isSafeInteger(quantity) || quantity <= 0)) return null;
  const total = data.amountTotal;
  if (!Number.isSafeInteger(total) || total < 0 ||
      typeof data.currency !== "string" || !/^[a-z]{3}$/i.test(data.currency)) return null;
  const bookCount = quantities.reduce((sum, quantity) => sum + quantity, 0);
  const currency = data.currency.toUpperCase();
  // Memoir's checkout prices are stored in cents and currently charge USD only.
  if (currency !== "USD") return null;
  const amount = `${currency} ${(total / 100).toFixed(2)}`;
  return {
    subject: `New Memoir book order — ${bookCount} book(s), ${amount}`,
    body: [
      `Order ids: ${data.orderIds.join(", ")}`,
      `Books: ${bookCount}`,
      `Paid: ${amount}`,
      "",
      "View order: https://memoirai-7db06.web.app/ops"
    ].join("\n")
  };
}

function createPaidBookOrderAlertHandler({ db, sendAlert, serverTimestamp, now = Date.now }) {
  return async (event) => {
    const ref = event.data?.ref;
    const alert = paidBookOrderAlert(event.data?.data(), event.params?.userId);
    if (!ref || !alert) return;
    const token = randomUUID();
    const claimed = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) return false;
      const delivery = snapshot.data()?.bookOrderEmail || {};
      if (delivery.sentAt) return false;
      if (Number(delivery.leaseUntilMs) > now()) {
        throw new Error("Book order email delivery is already in progress; retry later");
      }
      transaction.update(ref, {
        bookOrderEmail: { token, leaseUntilMs: now() + DELIVERY_LEASE_MS }
      });
      return true;
    });
    if (!claimed) return;
    try {
      const delivered = await sendAlert(alert.subject, alert.body, BOOK_ORDER_RECIPIENTS);
      if (!delivered) throw new Error("Book order email was not delivered");
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists) return;
        if (snapshot.data()?.bookOrderEmail?.token !== token) {
          throw new Error("Book order email delivery claim changed");
        }
        transaction.update(ref, {
          bookOrderEmail: { sentAt: serverTimestamp(), leaseUntilMs: 0 }
        });
      });
    } catch (error) {
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (snapshot.exists && snapshot.data()?.bookOrderEmail?.token === token) {
          transaction.update(ref, { bookOrderEmail: { leaseUntilMs: 0 } });
        }
      });
      throw error;
    }
  };
}

module.exports = { BOOK_ORDER_RECIPIENTS, paidBookOrderAlert, createPaidBookOrderAlertHandler };
