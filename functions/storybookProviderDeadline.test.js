const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
  mimeTypeForImageBuffer,
  openAITextRequestOptions,
  serializedGeminiRequestBody
} = require("./storybookAI");

const defaults = openAITextRequestOptions(undefined, 1_000);
assert.deepStrictEqual(defaults, { timeout: 30_000, maxRetries: 0 });

const bounded = openAITextRequestOptions(41_000, 1_000);
assert.strictEqual(bounded.timeout, 10_000);
assert.strictEqual(bounded.maxRetries, 0);

assert.throws(
  () => openAITextRequestOptions(1_500, 1_000),
  (error) => error && error.code === "worker-deadline"
);

assert.strictEqual(
  mimeTypeForImageBuffer(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  "image/png"
);
assert.strictEqual(mimeTypeForImageBuffer(Buffer.from([0xff, 0xd8, 0xff, 0xe0])), "image/jpeg");
assert.strictEqual(mimeTypeForImageBuffer(Buffer.from("not-an-image")), null);
assert.strictEqual(serializedGeminiRequestBody({ contents: [] }), "{\"contents\":[]}");
assert.throws(
  () => serializedGeminiRequestBody({ data: "x".repeat(20 * 1024 * 1024) }),
  (error) => error && error.code === "reference-payload-too-large"
);

const workerSource = fs.readFileSync(path.join(__dirname, "storybookWorker.js"), "utf8");
assert.match(
  workerSource,
  /generateBackCoverPitch\([\s\S]*?\{ deadlineAtMs: workerDeadlineAtMs \}/,
  "back-cover generation must inherit the worker deadline"
);
assert.match(
  workerSource,
  /if \(beforeAttempt\) await beforeAttempt\(\)/,
  "every provider retry must recheck account availability"
);
assert.match(
  workerSource,
  /beforeAttempt: verifyAccountAvailable/,
  "storybook provider calls must wire the account-deletion check"
);

console.log("storybook provider deadline tests passed");
