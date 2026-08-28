const assert = require("assert");
const {
  memoryIndexBelongsToUser,
  memoryIndexClaimDecision,
  memoryIndexOwner
} = require("./memoryIndexOwnership");

const missing = { exists: false, data: () => ({}) };
const victim = { exists: true, data: () => ({ ownerId: "victim" }) };

assert.strictEqual(memoryIndexOwner(missing), null);
assert.strictEqual(memoryIndexOwner(victim), "victim");
assert.strictEqual(memoryIndexClaimDecision(missing, "attacker"), "claim");
assert.strictEqual(memoryIndexClaimDecision(victim, "victim"), "owned");
assert.strictEqual(memoryIndexClaimDecision(victim, "attacker"), "collision");
assert.strictEqual(memoryIndexBelongsToUser(victim, "victim"), true);
assert.strictEqual(memoryIndexBelongsToUser(victim, "attacker"), false);

console.log("memoryIndexOwnership.test.js: all assertions passed");
