const assert = require("assert");
const fs = require("fs");
const path = require("path");

const rules = fs.readFileSync(path.join(__dirname, "..", "storage.rules"), "utf8");

assert.ok(
  rules.includes("function hasBlockingAccountOperation(userId)"),
  "storage rules must consolidate checkout and deletion state into one Firestore document"
);
assert.ok(
  rules.includes("function isActiveOwner(userId)")
    && rules.includes("return isOwner(userId)\n        && !hasBlockingAccountOperation(userId)"),
  "owner reads and listings must stop once account deletion begins"
);
assert.ok(
  !rules.includes("hasActiveCheckoutLock"),
  "every mutable Storage path must use the consolidated operation-lock check"
);
assert.ok(
  rules.includes(".data.state == 'deleting'") && rules.includes(".data.state == 'checkout'"),
  "the consolidated operation lock must block both deletion and active checkout"
);
assert.ok(
  rules.includes("!hasBlockingAccountOperation(userId)\n        && !isPaidBookVersion(userId, bookVersionId)"),
  "book writes must retain both operation-lock and paid-version immutability checks"
);
assert.ok(
  rules.includes("!hasBlockingAccountOperation(userId)\n        && !isDeletedAudio(userId, audioFile)"),
  "audio writes must retain both operation-lock and tombstone checks"
);
assert.ok(
  !rules.includes("documents/users/$(userId)/accessRequests/$(request.auth.uid)"),
  "shared audio reads must not combine tombstone, grant, and request lookups"
);
assert.ok(
  rules.includes("allow list: if isActiveOwner(userId);")
    && (rules.match(/allow read: if isActiveOwner\(userId\);/g) || []).length >= 7,
  "every owner-only Storage read path must honor the account operation lock"
);

console.log("storageRulesAccessBudget.test.js: all assertions passed");
