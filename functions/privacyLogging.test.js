const assert = require("node:assert/strict");
const {
  privacySafeLogDetails,
  safeErrorMetadata,
  safeLogIdentifier
} = require("./privacyLogging");

const token = safeLogIdentifier("user-secret-id");
assert.match(token, /^[a-f0-9]{12}$/);
assert.notEqual(token, "user-secret-id");
assert.equal(safeLogIdentifier(""), null);

const safeDetails = privacySafeLogDetails({
  userId: "user-secret-id",
  jobId: "job-secret-id",
  memoryId: "memory-secret-id",
  profileId: "profile-secret-id",
  count: 3
});
assert.deepEqual(Object.keys(safeDetails).sort(), [
  "count",
  "jobIdHash",
  "memoryIdHash",
  "profileIdHash",
  "userIdHash"
]);
assert.equal(safeDetails.count, 3);
assert.ok(!JSON.stringify(safeDetails).includes("secret-id"));

const safeError = safeErrorMetadata({
  name: "ProviderError",
  code: "ECONNRESET",
  status: 503,
  message: "private upstream response body"
});
assert.deepEqual(safeError, {
  errorName: "ProviderError",
  errorCode: "ECONNRESET",
  httpStatus: 503
});
assert.ok(!JSON.stringify(safeError).includes("private upstream"));

console.log("privacyLogging.test.js: all assertions passed");
