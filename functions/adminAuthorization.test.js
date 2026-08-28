const assert = require("assert");
const { isMemoirAdminToken, normalizedAllowedEmails } = require("./adminAuthorization");

assert.deepStrictEqual(normalizedAllowedEmails(" A@EXAMPLE.COM, b@example.com "), [
  "a@example.com",
  "b@example.com"
]);
assert.strictEqual(isMemoirAdminToken({ admin: true }, ""), true);
assert.strictEqual(isMemoirAdminToken({
  email: "admin@example.com", email_verified: true
}, "ADMIN@example.com"), true);
assert.strictEqual(isMemoirAdminToken({
  email: "admin@example.com", email_verified: false
}, "admin@example.com"), false);
assert.strictEqual(isMemoirAdminToken({
  email: "attacker@example.com", email_verified: true
}, "admin@example.com"), false);

console.log("adminAuthorization tests passed");
