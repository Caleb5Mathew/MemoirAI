const assert = require("assert");
const aiProxy = require("./aiProxy");
const { _test } = aiProxy;

assert.strictEqual(Object.keys(aiProxy).includes("_test"), false);

function assertInvalid(body) {
  assert.throws(() => _test.validateTranscriptionRequest(body), (error) => error.code === "invalid-argument");
}

assert.match(_test.transcriptionPrompt(), /personal memoir recording/);
assert.deepStrictEqual(
  _test.validateTranscriptionRequest({
    memoryId: "00000000-0000-0000-0000-000000000000",
    language: "EN",
    glossary: ["Rosalie", "Rosalie"]
  }),
  { memoryId: "00000000-0000-0000-0000-000000000000", language: "en", glossary: ["Rosalie"] }
);

assertInvalid({ memoryId: "00000000-0000-0000-0000-00000000000x" });
assertInvalid({ memoryId: "000000000000-0000-0000-0000-000000000000" });
assertInvalid({ memoryId: "00000000-0000-0000-0000-000000000000", language: "eng" });
assertInvalid({ memoryId: "00000000-0000-0000-0000-000000000000", glossary: [42] });
assertInvalid({ memoryId: "00000000-0000-0000-0000-000000000000", glossary: ["bad\nterm"] });
assertInvalid({
  memoryId: "00000000-0000-0000-0000-000000000000",
  glossary: ["x".repeat(81)]
});
assertInvalid({
  memoryId: "00000000-0000-0000-0000-000000000000",
  glossary: Array.from({ length: 41 }, (_, index) => `term-${index}`)
});

assert.throws(
  () => _test.validateTranscriptionAudio(Buffer.alloc(0)),
  (error) => error.code === "failed-precondition"
);
assert.throws(
  () => _test.validateTranscriptionAudio(Buffer.alloc(25 * 1024 * 1024 + 1)),
  (error) => error.code === "failed-precondition"
);
_test.validateTranscriptionAudio(Buffer.from("audio"));

assert.deepStrictEqual(
  _test.validateTranscriptionMetadata({ size: "1024", contentType: "audio/mp4", generation: "123" }),
  { size: 1024, generation: "123" }
);
assert.throws(
  () => _test.validateTranscriptionMetadata({ size: "0", contentType: "audio/mp4", generation: "123" }),
  (error) => error.code === "failed-precondition"
);
assert.throws(
  () => _test.validateTranscriptionMetadata({ size: "1024", contentType: "application/octet-stream", generation: "123" }),
  (error) => error.code === "failed-precondition"
);

const apiRequest = _test.buildTranscriptionAPIRequest("file", "en", ["Rosalie"]);
assert.deepStrictEqual(apiRequest.languages, ["en"]);
assert.deepStrictEqual(apiRequest.keywords, ["Rosalie"]);
assert.strictEqual(apiRequest.language, undefined);
assert.strictEqual(_test.buildTranscriptionAPIRequest("file", "en", []).keywords, undefined);

const uneditedUpdate = _test.buildTranscriptionUpdate({ transcriptionVersion: 2 }, "New transcript", "en");
assert.strictEqual(uneditedUpdate.transcription, "New transcript");
assert.strictEqual(uneditedUpdate.transcriptionVersion, 3);

const editedUpdate = _test.buildTranscriptionUpdate(
  { transcriptionVersion: 4, transcriptionEdited: "My corrected transcript" },
  "Retried raw transcript",
  "en"
);
assert.strictEqual(editedUpdate.transcription, undefined);
assert.strictEqual(editedUpdate.transcriptionRaw, "Retried raw transcript");
assert.strictEqual(editedUpdate.transcriptionVersion, 5);

const clearedUpdate = _test.buildTranscriptionUpdate(
  { transcriptionEdited: "" },
  "Retried raw transcript",
  "en"
);
assert.strictEqual(clearedUpdate.transcription, undefined);

assert.strictEqual(_test.normalizedTranscriptionVersion("bad"), 0);
assert.strictEqual(_test.normalizedTranscriptionVersion(-1), 0);
assert.strictEqual(_test.normalizedTranscriptionVersion(7), 7);

const audioHash = "a".repeat(64);
assert.deepStrictEqual(
  _test.transcriptionLeaseDecision(
    { transcriptionStatus: "completed", transcriptionAudioSHA256: audioHash, transcriptionRaw: "Saved" },
    audioHash,
    1000
  ),
  { action: "cached", text: "Saved" }
);
assert.deepStrictEqual(
  _test.transcriptionLeaseDecision(
    {
      transcriptionStatus: "processing",
      transcriptionAudioSHA256: audioHash,
      transcriptionJobId: "job",
      transcriptionLeaseExpiresAt: { toMillis: () => 2000 }
    },
    audioHash,
    1000
  ),
  { action: "processing" }
);
assert.deepStrictEqual(
  _test.transcriptionLeaseDecision(
    {
      transcriptionStatus: "processing",
      transcriptionAudioSHA256: audioHash,
      transcriptionJobId: "job",
      transcriptionLeaseExpiresAt: { toMillis: () => 900 }
    },
    audioHash,
    1000
  ),
  { action: "claim" }
);

console.log("transcriptionValidation.test.js: all assertions passed");
