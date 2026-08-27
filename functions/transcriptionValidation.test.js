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

function syntheticM4A(durationSeconds) {
  const mvhd = Buffer.alloc(28);
  mvhd.writeUInt32BE(mvhd.length, 0);
  mvhd.write("mvhd", 4, "ascii");
  mvhd.writeUInt8(0, 8);
  mvhd.writeUInt32BE(1000, 20);
  mvhd.writeUInt32BE(durationSeconds * 1000, 24);
  const moov = Buffer.alloc(8 + mvhd.length);
  moov.writeUInt32BE(moov.length, 0);
  moov.write("moov", 4, "ascii");
  mvhd.copy(moov, 8);
  return moov;
}

assert.strictEqual(_test.m4aDurationSeconds(syntheticM4A(3600)), 3600);
assert.strictEqual(_test.validateTranscriptionDuration(syntheticM4A(3600)), 3600);
assert.throws(
  () => _test.validateTranscriptionDuration(syntheticM4A(3601)),
  (error) => error.code === "failed-precondition"
);
assert.throws(
  () => _test.validateTranscriptionDuration(Buffer.from("not an m4a")),
  (error) => error.code === "failed-precondition"
);

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

assert.deepStrictEqual(
  _test.transcriptionBudgetDecision(
    { count: 1, audioBytes: 1024, audioDurationSeconds: 60 },
    { count: 2, audioBytes: 2048, audioDurationSeconds: 120 },
    4096,
    30.2
  ),
  {
    allowed: true,
    userCount: 2,
    userAudioBytes: 5120,
    userAudioDurationSeconds: 91,
    globalCount: 3,
    globalAudioBytes: 6144,
    globalAudioDurationSeconds: 151
  }
);
assert.deepStrictEqual(
  _test.transcriptionBudgetDecision({ count: 10 }, {}, 1, 1),
  { allowed: false, reason: "user-request-limit" }
);
assert.deepStrictEqual(
  _test.transcriptionBudgetDecision({ audioBytes: 100 * 1024 * 1024 }, {}, 1, 1),
  { allowed: false, reason: "user-audio-limit" }
);
assert.deepStrictEqual(
  _test.transcriptionBudgetDecision({ audioDurationSeconds: 3 * 60 * 60 }, {}, 1, 1),
  { allowed: false, reason: "user-duration-limit" }
);
assert.deepStrictEqual(
  _test.transcriptionBudgetDecision({}, { count: 100 }, 1, 1),
  { allowed: false, reason: "global-request-limit" }
);
assert.deepStrictEqual(
  _test.transcriptionBudgetDecision({}, { audioBytes: 400_000_000 }, 1, 1),
  { allowed: false, reason: "global-audio-limit" }
);
assert.deepStrictEqual(
  _test.transcriptionBudgetDecision({}, { audioDurationSeconds: 18 * 60 * 60 }, 1, 1),
  { allowed: false, reason: "global-duration-limit" }
);
assert.deepStrictEqual(
  _test.transcriptionBudgetDecision({}, {}, 0, 1),
  { allowed: false, reason: "invalid-audio-size" }
);
assert.deepStrictEqual(
  _test.transcriptionBudgetDecision({}, {}, 1, 0),
  { allowed: false, reason: "invalid-audio-duration" }
);

assert.strictEqual(_test.transcriptionAttemptBucket(Date.UTC(2026, 7, 27, 18, 23, 59)), "202608271823");
assert.strictEqual(_test.transcriptionAttemptBucket(Number.NaN), null);
assert.deepStrictEqual(
  _test.transcriptionAttemptDecision(5, 29),
  { allowed: true, userCount: 6, globalCount: 30 }
);
assert.deepStrictEqual(
  _test.transcriptionAttemptDecision(6, 0),
  { allowed: false, reason: "user-attempt-limit" }
);
assert.deepStrictEqual(
  _test.transcriptionAttemptDecision(0, 30),
  { allowed: false, reason: "global-attempt-limit" }
);

function fakeAttemptDatabase(userCount, globalCount) {
  const userRef = { scope: "user" };
  const globalRef = { scope: "global" };
  const writes = [];
  return {
    writes,
    collection(name) {
      if (name === "users") {
        return {
          doc() {
            return { collection: () => ({ doc: () => userRef }) };
          }
        };
      }
      return { doc: () => globalRef };
    },
    async runTransaction(operation) {
      await operation({
        async get(ref) {
          const count = ref.scope === "user" ? userCount : globalCount;
          return { exists: count > 0, data: () => ({ count }) };
        },
        set(ref, data) {
          writes.push({ scope: ref.scope, count: data.count });
        }
      });
    }
  };
}

async function runProbedDurationAssertions() {
  const audio = syntheticM4A(60);
  const validProbe = async () => ({
    codec_name: "aac", profile: "LC", sample_rate: "48000", channels: 1, nb_read_frames: "2813"
  });
  assert.strictEqual(_test.frameCountDurationSeconds(await validProbe()), 60.010666666666665);
  assert.strictEqual(await _test.validateProbedTranscriptionDuration(audio, validProbe), 60.010666666666665);

  await assert.rejects(
    _test.validateProbedTranscriptionDuration(audio, async () => {
      throw new Error("invalid media");
    }),
    (error) => error.code === "failed-precondition"
  );
  await assert.rejects(
    _test.validateProbedTranscriptionDuration(audio, async () => ({
      codec_name: "mp3", profile: "LC", sample_rate: "48000", channels: 1, nb_read_frames: "2813"
    })),
    (error) => error.code === "failed-precondition"
  );
  await assert.rejects(
    _test.validateProbedTranscriptionDuration(audio, async () => ({
      codec_name: "aac", profile: "HE-AAC", sample_rate: "48000", channels: 1, nb_read_frames: "2813"
    })),
    (error) => error.code === "failed-precondition"
  );
  await assert.rejects(
    _test.validateProbedTranscriptionDuration(audio, async () => ({
      codec_name: "aac", profile: "LC", sample_rate: "48000", channels: 1, nb_read_frames: "168751"
    })),
    (error) => error.code === "failed-precondition"
  );
  await assert.rejects(
    _test.validateProbedTranscriptionDuration(audio, async () => ({
      codec_name: "aac", profile: "LC", sample_rate: "48000", channels: 1, nb_read_frames: "1407"
    })),
    (error) => error.code === "failed-precondition"
  );

  const realAACWithForgedOneSecondHeaders = Buffer.from(
    "AAAAHGZ0eXBNNEEgAAACAE00QSBpc29taXNvMgAAAAhmcmVlAAAA6W1kYXTeAgBMYXZjNjIuMjguMTAwAAIwQA4BGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcAAAPLbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAA+gAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAvV0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAADLIAAAAAAAAAAAAAAAEBAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAyyAAAEAAABAAAAAAJtbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAA+gAAAPoBVxAAAAAAALWhkbHIAAAAAAAAAAHNvdW4AAAAAAAAAAAAAAABTb3VuZEhhbmRsZXIAAAACGG1pbmYAAAAQc21oZAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAB3HN0YmwAAABqc3RzZAAAAAAAAAABAAAAWm1wNGEAAAAAAAAAAQAAAAAAAAAAAAEAEAAAAAA+gAAAAAAANmVzZHMAAAAAA4CAgCUAAQAEgICAF0AVAAAAAAAfQAAAAh8FgICABRQIVuUABoCAgAECAAAAIHN0dHMAAAAAAAAAAgAAADMAAAQAAAAAAQAAAyAAAAAcc3RzYwAAAAAAAAABAAAAAQAAADQAAAABAAAA5HN0c3oAAAAAAAAAAAAAADQAAAAVAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAFHN0Y28AAAAAAAAAAQAAACwAAAAac2dwZAEAAAByb2xsAAAAAgAAAAH//wAAABxzYmdwAAAAAHJvbGwAAAABAAAANAAAAAEAAABidWR0YQAAAFptZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAAC1pbHN0AAAAJal0b28AAAAdZGF0YQAAAAEAAAAATGF2ZjYyLjEyLjEwMA==",
    "base64"
  );
  await assert.rejects(
    _test.validateProbedTranscriptionDuration(realAACWithForgedOneSecondHeaders),
    (error) => error.code === "failed-precondition"
  );

  const allowedAttempts = fakeAttemptDatabase(1, 2);
  await _test.checkAndIncrementTranscriptionAttempts(
    "user-1",
    Date.UTC(2026, 7, 27, 18, 23),
    allowedAttempts
  );
  assert.deepStrictEqual(allowedAttempts.writes, [
    { scope: "user", count: 2 },
    { scope: "global", count: 3 }
  ]);
  await assert.rejects(
    _test.checkAndIncrementTranscriptionAttempts(
      "user-1",
      Date.UTC(2026, 7, 27, 18, 23),
      fakeAttemptDatabase(6, 0)
    ),
    (error) => error.code === "resource-exhausted"
  );
  await assert.rejects(
    _test.checkAndIncrementTranscriptionAttempts(
      "user-1",
      Date.UTC(2026, 7, 27, 18, 23),
      fakeAttemptDatabase(0, 30)
    ),
    (error) => error.code === "resource-exhausted"
  );
}

runProbedDurationAssertions()
  .then(() => console.log("transcriptionValidation.test.js: all assertions passed"))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
