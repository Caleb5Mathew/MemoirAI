const assert = require("assert");
const fs = require("fs");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

const cartCommitStart = source.indexOf("async function commitPaidCartCheckoutFromStripeSession");
const singleCommitStart = source.indexOf("async function commitPaidSingleCheckoutFromStripeSession");
const webhookStart = source.indexOf("exports.stripeWebhook", singleCommitStart);

assert.ok(cartCommitStart >= 0, "cart paid-commit function must exist");
assert.ok(singleCommitStart > cartCommitStart, "single paid-commit function must exist");
assert.ok(webhookStart > singleCommitStart, "Stripe webhook must follow paid-commit functions");

const cartCommit = source.slice(cartCommitStart, singleCommitStart);
const singleCommit = source.slice(singleCommitStart, webhookStart);

assert.match(
  source,
  /pendingSingleCheckouts"\)\.doc\(session\.id\)\.set\(\{[\s\S]*?expectedFulfillmentItem,/,
  "single checkout must persist the exact artifact fingerprint used before payment"
);

for (const [name, body] of [["cart", cartCommit], ["single", singleCommit]]) {
  assert.ok(
    body.includes("validateCheckoutBookArtifacts({"),
    `${name} paid commit must revalidate the priced artifact fingerprint`
  );
  assert.ok(
    body.includes('status: "paid_fulfillment_hold"'),
    `${name} paid commit must durably hold changed artifacts`
  );
  assert.ok(
    body.includes('fulfillmentHoldReason: "book_artifacts_changed_after_payment"'),
    `${name} artifact hold must state the remediation reason`
  );
}

console.log("paidCheckoutArtifactGuard.test.js: all assertions passed");
