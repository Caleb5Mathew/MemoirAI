const assert = require("assert");
const fs = require("fs");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "storybookWorker.js"), "utf8");
const forbiddenLogPayloads = [
  "transcription: m.transcription",
  "characterDetails: m.characterDetails",
  "characterDetailsEnriched: enrichedDetailsStr",
  "characterContext: String(characterContext",
  "sceneDescription });",
  "characterList: String(characterList",
  "chunk: assembled.slice",
  "geminiTextResponse: e?.geminiTextResponse",
  "stack: e?.stack",
  "message: String(e?.message || e)"
];

for (const forbidden of forbiddenLogPayloads) {
  assert.ok(!source.includes(forbidden), `sensitive storybook log payload returned: ${forbidden}`);
}

assert.ok(
  !/logJob\("storybook\.title",\s*\{[\s\S]{0,240}extractedTitle/.test(source),
  "sensitive extracted title returned to storybook logs"
);
assert.ok(
  !/logJob\("storybook\.jobStart",\s*\{[\s\S]{0,600}(profileName|profileEthnicity):\s*data\./.test(source),
  "sensitive profile fields returned to storybook start logs"
);

console.log("storybookLoggingPrivacy.test.js: all assertions passed");
