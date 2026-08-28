const assert = require("assert");
const { MAX_RETRY_SLEEP_MS, boundedRetryDelayMs } = require("./retryDeadlinePolicy");

assert.strictEqual(boundedRetryDelayMs({
  baseDelayMs: 15_000,
  serverDelayMs: 465_000,
  jitterFraction: 0.2,
  nowMs: 0,
  deadlineMs: 500_000
}), MAX_RETRY_SLEEP_MS);

assert.strictEqual(boundedRetryDelayMs({
  baseDelayMs: 15_000,
  serverDelayMs: 30_000,
  jitterFraction: 0,
  nowMs: 480_000,
  deadlineMs: 500_000
}), 10_000);

assert.strictEqual(boundedRetryDelayMs({
  baseDelayMs: 15_000,
  serverDelayMs: 30_000,
  jitterFraction: 0,
  nowMs: 490_000,
  deadlineMs: 500_000
}), null);

console.log("retryDeadlinePolicy.test.js: all assertions passed");
