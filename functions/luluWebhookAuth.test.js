const assert = require("assert");
const crypto = require("crypto");
const { verifyLuluWebhookSignature } = require("./luluWebhookAuth");

const body = Buffer.from('{"event_type":"PRINT_JOB_STATUS_CHANGED"}');
const signature = crypto.createHmac("sha256", "webhook-secret").update(body).digest("hex");

assert.ok(verifyLuluWebhookSignature(body, signature, "webhook-secret"));
assert.ok(!verifyLuluWebhookSignature(body, signature, "oauth-client-secret"));
assert.ok(!verifyLuluWebhookSignature(body, "not-hex", "webhook-secret"));
console.log("luluWebhookAuth.test.js: all assertions passed");
