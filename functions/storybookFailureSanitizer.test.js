const assert = require("assert");
const { sanitizeStorybookFailure } = require("./storybookFailureSanitizer");

const sensitive = "private transcript: my medical history and family names";
const failure = sanitizeStorybookFailure({
  message: sensitive,
  stack: sensitive,
  geminiTextResponse: sensitive,
  status: 503,
  name: "ProviderError",
  geminiBlockReason: "SAFETY",
  geminiFinishReason: "STOP"
}, "image", "timestamp");

assert.deepStrictEqual(failure, {
  stage: "image",
  message: "The illustration service could not generate this image.",
  at: "timestamp",
  httpStatus: 503,
  errorName: "ProviderError",
  geminiFinishReason: "STOP",
  geminiBlockReason: "SAFETY"
});
assert.ok(!JSON.stringify(failure).includes(sensitive));

const malformed = sanitizeStorybookFailure({
  name: "bad name with private content",
  status: 200
}, "private-stage-name", null);
assert.strictEqual(malformed.stage, "unknown");
assert.strictEqual(malformed.errorName, undefined);
assert.strictEqual(malformed.httpStatus, undefined);

console.log("storybookFailureSanitizer.test.js: all assertions passed");
