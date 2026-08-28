const test = require("node:test");
const assert = require("node:assert/strict");
const {
  fallbackBackCoverPitch,
  isUsableBackCoverPitch
} = require("./storybookAI");

test("rejects a truncated Gemini back-cover fragment", () => {
  assert.equal(
    isUsableBackCoverPitch("Daniel Reed invites you into a life beautifully crafted from"),
    false
  );
});

test("accepts complete multi-sentence back-cover copy", () => {
  const pitch = "Step into the moments that shaped a remarkable life, from family traditions to brave new beginnings. Told with warmth and honesty, these stories preserve the people, places, and choices that mattered most. This keepsake is ready to be shared across generations.";
  assert.equal(isUsableBackCoverPitch(pitch), true);
});

test("fallback copy is complete and includes the profile name", () => {
  const pitch = fallbackBackCoverPitch("  Daniel   Reed  ");
  assert.match(pitch, /Daniel Reed's life/);
  assert.equal(isUsableBackCoverPitch(pitch), true);
});

test("fallback copy remains complete without a profile name", () => {
  assert.equal(isUsableBackCoverPitch(fallbackBackCoverPitch("")), true);
});
