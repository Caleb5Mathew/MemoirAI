const assert = require("assert");
const {
  MAX_RETRY_SLEEP_MS,
  boundedProviderRequestTimeoutMs,
  boundedRetryDelayMs,
  canStartProviderAttempt,
  isRetryableProviderError
} = require("./retryDeadlinePolicy");

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

assert.strictEqual(boundedProviderRequestTimeoutMs({
  maximumTimeoutMs: 180_000,
  nowMs: 300_000,
  deadlineMs: 500_000
}), 170_000);

assert.strictEqual(boundedProviderRequestTimeoutMs({
  maximumTimeoutMs: 180_000,
  nowMs: 470_000,
  deadlineMs: 500_000
}), null);

assert.strictEqual(canStartProviderAttempt({
  nowMs: 300_000,
  deadlineMs: 500_000,
  minimumExecutionMs: 120_000
}), true);

assert.strictEqual(canStartProviderAttempt({
  nowMs: 360_001,
  deadlineMs: 500_000,
  minimumExecutionMs: 120_000
}), false);

for (const status of [429, 500, 502, 503, 504]) {
  assert.strictEqual(isRetryableProviderError({ status }), true);
}
assert.strictEqual(isRetryableProviderError({ cause: { code: "ECONNRESET" } }), true);
assert.strictEqual(isRetryableProviderError({ status: 400 }), false);

console.log("retryDeadlinePolicy.test.js: all assertions passed");
