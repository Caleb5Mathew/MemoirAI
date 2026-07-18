const assert = require("assert");
const { parseLeakDetectorResponse } = require("./storybookAI");

function candidate(text) {
  return { candidates: [{ content: { parts: [{ text }] } }] };
}

// Clean JSON verdicts
assert.strictEqual(parseLeakDetectorResponse(candidate('{"hasEmbeddedPhoto": true}')), true);
assert.strictEqual(parseLeakDetectorResponse(candidate('{"hasEmbeddedPhoto": false}')), false);

// Markdown-fenced JSON (Gemini wraps despite responseMimeType sometimes)
assert.strictEqual(parseLeakDetectorResponse(candidate('```json\n{"hasEmbeddedPhoto": true}\n```')), true);
assert.strictEqual(parseLeakDetectorResponse(candidate('```\n{"hasEmbeddedPhoto": false}\n```')), false);

// Bare token fallbacks
assert.strictEqual(parseLeakDetectorResponse(candidate("YES")), true);
assert.strictEqual(parseLeakDetectorResponse(candidate("No, the image is clean.")), false);

// Fail-open on garbage, wrong types, and missing structure
assert.strictEqual(parseLeakDetectorResponse(candidate('{"hasEmbeddedPhoto": "true"}')), false);
assert.strictEqual(parseLeakDetectorResponse(candidate("maybe?")), false);
assert.strictEqual(parseLeakDetectorResponse(candidate("")), false);
assert.strictEqual(parseLeakDetectorResponse({}), false);
assert.strictEqual(parseLeakDetectorResponse(null), false);
assert.strictEqual(parseLeakDetectorResponse(undefined), false);

console.log("leakDetectorParsing.test.js: all assertions passed");
