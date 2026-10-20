"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { BOOK_ORDER_RECIPIENTS, paidBookOrderAlert, createPaidBookOrderAlertHandler } = require("./paidBookOrderAlerts");

function fixture(overrides = {}) {
  return {
    userId: "user1", stripeSessionId: "cs_live_example", isTestOrder: false,
    paidAt: { seconds: 123 }, orderIds: ["order1"], items: [{ quantity: 1 }],
    amountTotal: 2999, currency: "usd", ...overrides
  };
}

function harness(data = fixture(), sendAlert = async () => true) {
  let record = structuredClone(data);
  let clock = 1000;
  let tail = Promise.resolve();
  const ref = {};
  const db = {
    runTransaction(callback) {
      const work = tail.then(async () => {
        let update;
        const result = await callback({
          get: async () => ({ exists: record !== null, data: () => structuredClone(record) }),
          update: (_, value) => { update = value; }
        });
        if (update) record = { ...record, ...update };
        return result;
      });
      tail = work.catch(() => {});
      return work;
    }
  };
  const calls = [];
  const handler = createPaidBookOrderAlertHandler({
    db, now: () => clock, serverTimestamp: () => "timestamp",
    sendAlert: async (...args) => { calls.push(args); return sendAlert(...args); }
  });
  return {
    handler, calls, record: () => record,
    event: { params: { userId: "user1" }, data: { ref, data: () => data } },
    expire: () => { clock += 300001; },
    remove: () => { record = null; }
  };
}

test("single-book email includes only order summary and requested recipients", async () => {
  const h = harness(fixture({ customerEmail: "private@example.com", shippingAddress: { city: "Private City" } }));
  await h.handler(h.event);
  assert.equal(h.calls.length, 1);
  assert.deepEqual(h.calls[0][2], ["caleb5mathew@gmail.com", "calebmathew2121@gmail.com"]);
  assert.match(h.calls[0][0], /1 book\(s\), USD 29.99/);
  assert.doesNotMatch(h.calls[0][1], /private|Private/);
  assert.equal(h.record().bookOrderEmail.sentAt, "timestamp");
});

test("cart quantities produce a single grouped email", async () => {
  const h = harness(fixture({ orderIds: ["one", "two"], items: [{ quantity: 2 }, { quantity: 1 }], amountTotal: 8997 }));
  await h.handler(h.event);
  assert.equal(h.calls.length, 1);
  assert.match(h.calls[0][0], /3 book\(s\), USD 89.97/);
  assert.match(h.calls[0][1], /one, two/);
});

test("test, unverified, mismatched and malformed checkouts do not email", async () => {
  const invalid = [
    { isTestOrder: true }, { isTestOrder: undefined }, { userId: "other" },
    { stripeSessionId: "" }, { paidAt: null }, { orderIds: [] }, { orderIds: [null] },
    { items: [] }, { items: [{ quantity: 0 }] }, { amountTotal: -1 },
    { amountTotal: null }, { currency: "nonsense" }
  ];
  for (const change of invalid) {
    const h = harness(fixture(change));
    await h.handler(h.event);
    assert.equal(h.calls.length, 0, JSON.stringify(change));
  }
  assert.equal(paidBookOrderAlert(null, "user1"), null);
});

test("repeat delivery uses persisted sent marker", async () => {
  const h = harness();
  await h.handler(h.event);
  await h.handler(h.event);
  assert.equal(h.calls.length, 1);
});

test("concurrent event retries while first sender owns lease", async () => {
  let release;
  let entered;
  const ready = new Promise((resolve) => { entered = resolve; });
  const h = harness(fixture(), () => { entered(); return new Promise((resolve) => { release = resolve; }); });
  const first = h.handler(h.event);
  await ready;
  await assert.rejects(h.handler(h.event), /already in progress/);
  release(true);
  await first;
  await h.handler(h.event);
  assert.equal(h.calls.length, 1);
});

test("failed SMTP delivery clears lease and permits retry", async () => {
  let success = false;
  const h = harness(fixture(), async () => success);
  await assert.rejects(h.handler(h.event), /not delivered/);
  assert.equal(h.record().bookOrderEmail.leaseUntilMs, 0);
  success = true;
  await h.handler(h.event);
  assert.equal(h.calls.length, 2);
  assert.equal(h.record().bookOrderEmail.sentAt, "timestamp");
});

test("expired delivery lease recovers after a terminated invocation", async () => {
  const h = harness(fixture({ bookOrderEmail: { token: "old", leaseUntilMs: 2000 } }));
  await assert.rejects(h.handler(h.event), /already in progress/);
  h.expire();
  await h.handler(h.event);
  assert.equal(h.calls.length, 1);
});

test("deleted checkout is not emailed", async () => {
  const h = harness();
  h.remove();
  await h.handler(h.event);
  assert.equal(h.calls.length, 0);
  assert.equal(BOOK_ORDER_RECIPIENTS.length, 2);
});

test("SMTP helper preserves existing recipients and sender, and rejects partial delivery", async () => {
  const messages = [];
  let rejected = [];
  const context = {
    module: { exports: {} }, URL, console: { log() {}, warn() {}, error() {} },
    require(name) {
      if (name === "firebase-functions/params") {
        return { defineSecret: () => ({ value: () => "smtps://sender%40example.com:secret@smtp.example.com:465" }) };
      }
      if (name === "nodemailer") {
        return { createTransport: () => ({ sendMail: async (message) => { messages.push(message); return { rejected }; } }) };
      }
      throw new Error(`Unexpected dependency ${name}`);
    }
  };
  vm.runInNewContext(fs.readFileSync(require.resolve("./opsAlerts"), "utf8"), context);
  const { sendOpsAlert } = context.module.exports;
  assert.equal(await sendOpsAlert("Existing alert", "Body"), true);
  assert.equal(messages[0].to, "memoirstorybook@gmail.com");
  assert.equal(messages[0].from, "sender@example.com");
  assert.equal(await sendOpsAlert("New alert", "Body", BOOK_ORDER_RECIPIENTS), true);
  assert.deepEqual(messages[1].to, BOOK_ORDER_RECIPIENTS);
  rejected = [BOOK_ORDER_RECIPIENTS[1]];
  assert.equal(await sendOpsAlert("Partial", "Body", BOOK_ORDER_RECIPIENTS), false);
});
