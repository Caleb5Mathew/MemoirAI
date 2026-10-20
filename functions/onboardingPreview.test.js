const assert = require("assert");
const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({
  projectId: "demo-memoir",
  storageBucket: "demo-memoir.appspot.com"
});
const {
  sanitizeOnboardingPreviewRequest,
  onboardingPreviewRequestHash,
  buildOnboardingIllustrationPrompt,
  previewTitle
} = require("./onboardingPreview")._test;

const uid = "user-123";
const valid = {
  requestId: "preview_123",
  profileId: "550e8400-e29b-41d4-a716-446655440000",
  memoryId: "67e55044-10b1-426f-9247-bb680e5fe0c8",
  profileName: " Alex ",
  storyText: " When I was eight, my dad fixed an old radio. ",
  subjectPhotoStoragePath: "users/user-123/profiles/550e8400-e29b-41d4-a716-446655440000/subjectPhoto.jpg"
};

{
  const value = sanitizeOnboardingPreviewRequest(valid, uid);
  assert.equal(value.profileName, "Alex");
  assert.equal(value.storyText, "When I was eight, my dad fixed an old radio.");
  assert.equal(value.profileId, valid.profileId);
}

for (const [key, value] of [
  ["requestId", "bad id"],
  ["profileId", "not-a-uuid"],
  ["memoryId", "not-a-uuid"],
  ["profileName", "  "],
  ["storyText", ""]
]) {
  assert.throws(() => sanitizeOnboardingPreviewRequest({ ...valid, [key]: value }, uid));
}

assert.throws(() => sanitizeOnboardingPreviewRequest({
  ...valid,
  subjectPhotoStoragePath: "users/another-user/profiles/550e8400-e29b-41d4-a716-446655440000/subjectPhoto.jpg"
}, uid));

{
  const value = sanitizeOnboardingPreviewRequest(valid, uid);
  assert.equal(onboardingPreviewRequestHash(value), onboardingPreviewRequestHash({ ...value }));
  assert.notEqual(onboardingPreviewRequestHash(value), onboardingPreviewRequestHash({ ...value, storyText: "Changed" }));
}

{
  const prompt = buildOnboardingIllustrationPrompt({
    profileName: "Alex",
    storyText: valid.storyText,
    hasHeadshot: true,
    hasStyleReference: true
  });
  assert(prompt.includes("Every parent, friend, spouse, child"));
  assert(prompt.includes("Alex re-aged"));
  assert(prompt.includes("MUST NOT copy the portrait's face, hair, facial hair, or clothing"));
  assert(prompt.includes("No words"));
  const { artStyleMemoryIllustrationStyleDescription } = require("./storybookAI");
  assert(prompt.includes(artStyleMemoryIllustrationStyleDescription("kidsBook")));
  assert(prompt.includes("REFERENCE IMAGE #1 is the children's-book STYLE ANCHOR"));
  assert(prompt.includes("REFERENCE IMAGE #2 is the book subject's IDENTITY ONLY"));
  assert(prompt.includes("Do NOT copy photographic lighting"));
  assert(!prompt.includes("editorial storybook"));
  assert(!prompt.includes("undefined"));
}

assert.equal(previewTitle("Dad fixed the old radio."), "The old radio");
assert.equal(previewTitle("I learned to ride my bike."), "The bicycle");
assert.equal(previewTitle("We spent the day at school."), "A school-day memory");
assert.equal(previewTitle("A quiet afternoon."), "A memory I carry");

{
  const { timestampMillis } = require("./onboardingPreview")._test;
  assert.equal(timestampMillis(new Date("2026-10-19T00:00:00Z")), 1792368000000);
  assert(Number.isNaN(timestampMillis(null)));
}

console.log("onboarding preview tests passed");

{
  assert.equal(sanitizeOnboardingPreviewRequest(valid, uid).storytellerRole, "subject");
  const helper = sanitizeOnboardingPreviewRequest({ ...valid, storytellerRole: "helper" }, uid);
  assert.equal(helper.storytellerRole, "helper");
  assert.throws(() => sanitizeOnboardingPreviewRequest({ ...valid, storytellerRole: "someone" }, uid));
  assert.notEqual(onboardingPreviewRequestHash(helper), onboardingPreviewRequestHash(sanitizeOnboardingPreviewRequest(valid, uid)));
  const legacy = sanitizeOnboardingPreviewRequest(valid, uid);
  delete legacy.storytellerRole;
  assert.equal(onboardingPreviewRequestHash(legacy), onboardingPreviewRequestHash(sanitizeOnboardingPreviewRequest(valid, uid)));
  const prompt = buildOnboardingIllustrationPrompt({
    profileName: "Alex", storyText: "My dad played in fields as a boy.", hasHeadshot: true, storytellerRole: "helper"
  });
  assert.match(prompt, /The helper and Alex are different people/);
  assert.match(prompt, /portrait shows Alex, the book subject/);
  assert.match(prompt, /First-person words such as "I" and "my" refer to the helper/);
  assert.match(prompt, /do not convert a helper's account/);
  assert(!prompt.includes("MEMORY, TOLD BY ALEX"));
  assert.equal(previewTitle("Quiet afternoons.", "helper"), "A memory to keep");
}

const { createOnboardingPreviewHandler, onboardingAgeDirection, refineOnboardingStory, onboardingPreviewLimit, loadOwnedSubjectPhoto } = require('./onboardingPreview')._test;
assert.match(onboardingAgeDirection(), /visual casting assumption, never a biographical fact/);
assert.match(onboardingAgeDirection(), /explicitly concerns adulthood/);
assert.match(onboardingAgeDirection(), /do not copy gray hair/);

function fakeDatabase() {
  const records = new Map();
  function ref(path) {
    return {
      path,
      collection: name => ({ doc: id => ref(`${path}/${name}/${id}`) }),
      get: async () => ({ exists: records.has(path), data: () => records.get(path) }),
      update: async data => records.set(path, { ...records.get(path), ...data })
    };
  }
  return {
    records,
    collection: name => ({ doc: id => ref(`${name}/${id}`) }),
    runTransaction: async action => action({
      get: reference => reference.get(),
      update: (reference, data) => records.set(reference.path, { ...records.get(reference.path), ...data }),
      set: (reference, data) => records.set(reference.path, data),
      create: (reference, data) => records.set(reference.path, data)
    })
  };
}

(async () => {
  const scopedPhotoPath = `users/${uid}/onboardingPreviews/${valid.requestId}/subjectPhoto.jpg`;
  assert.equal(sanitizeOnboardingPreviewRequest({ ...valid, subjectPhotoStoragePath: scopedPhotoPath }, uid).subjectPhotoStoragePath, scopedPhotoPath);
  assert.throws(() => sanitizeOnboardingPreviewRequest({ ...valid, subjectPhotoStoragePath: scopedPhotoPath.replace(valid.requestId, "another-request") }, uid));
  let downloadedPath;
  const photoBytes = Buffer.from("ffd8ffdb", "hex");
  const photoBucket = { file: path => {
    downloadedPath = path;
    return { getMetadata: async () => [{ contentType: "image/jpeg", size: photoBytes.length }], download: async () => [photoBytes] };
  } };
  const photoInput = { bucket: photoBucket, userId: uid, profileId: valid.profileId, requestId: valid.requestId, storagePath: scopedPhotoPath };
  assert.deepEqual(await loadOwnedSubjectPhoto(photoInput), photoBytes);
  assert.equal(downloadedPath, scopedPhotoPath);
  await assert.rejects(loadOwnedSubjectPhoto({ ...photoInput, requestId: "different-request" }), { code: "invalid-argument" });
  assert.deepEqual(await loadOwnedSubjectPhoto({ ...photoInput, storagePath: valid.subjectPhotoStoragePath }), photoBytes);
  assert.equal(onboardingPreviewLimit({ token: { onboardingPreviewTester: true } }), 50);
  assert.equal(onboardingPreviewLimit({ token: { onboardingPreviewTester: "true" } }), 1);
  assert.equal(onboardingPreviewLimit({ onboardingPreviewTester: true }), 1);
  assert.equal(onboardingPreviewLimit({ token: { admin: true } }), 1);
  const fallback = await refineOnboardingStory({ rawText: 'Um, I loved the old radio.', profileName: 'Alex' });
  assert.equal(fallback.text, 'I loved the old radio.');
  const db = fakeDatabase();
  let imageCalls = 0;
  let editingStarted = false;
  let savedMetadata;
  const handler = createOnboardingPreviewHandler({
    db,
    bucket: { file: () => ({ save: async (buffer, options) => { savedMetadata = options.metadata; } }) },
    geminiApiKey: 'test',
    generateTitle: async () => 'Rain and Radio Music',
    refineStory: async () => { editingStarted = true; return { text: 'When I was eight, my dad fixed an old radio.', model: 'test-editor' }; },
    generateImage: async (key, prompt, size, references, options) => {
      const { GEMINI_IMAGE_MODEL, loadStyleReferencePng } = require("./storybookAI");
      assert.equal(references.length, 1, "No-headshot previews still receive the book style anchor");
      if (options.model === GEMINI_IMAGE_MODEL) {
        assert.deepEqual(references[0], loadStyleReferencePng("normal"));
        assert(prompt.includes("STYLE ANCHOR"));
      } else {
        assert.equal(options.model, "gemini-3.1-flash-lite-image");
        assert(references[0].length < 200000);
        assert(prompt.includes("STYLE ONLY"));
      }
      imageCalls++;
      // The owned-copy lookup starts concurrently; image work must not wait for editing.
      return Buffer.from('89504e470d0a1a0a', 'hex');
    }
  });
  await assert.rejects(handler({ data: { warmup: true } }), { code: "unauthenticated" });
  assert.deepEqual(await handler({ auth: { uid }, data: { warmup: true } }), { status: "ready" });
  assert.equal(db.records.size, 0, "Warmup must not reserve quota or create a job");
  assert.equal(imageCalls, 0, "Warmup must not call the image provider");
  assert.equal(editingStarted, false, "Warmup must not call the editor");
  await assert.rejects(handler({ auth: { uid }, data: { warmup: "true" } }), { code: "invalid-argument" });
  db.records.set(`accountDeletionRequests/${uid}`, { status: "pending" });
  await assert.rejects(handler({ auth: { uid }, data: { warmup: true } }), { accountDeletionRequested: true });
  db.records.delete(`accountDeletionRequests/${uid}`);
  const request = { auth: { uid }, data: { ...valid, subjectPhotoStoragePath: null } };
  const first = await handler(request);
  assert(editingStarted, "Typed memories still receive reading refinement");
  for (const stage of ["admission", "ownedReadingLookup", "reading", "title", "photo", "image", "storage", "generation", "overall"]) {
    assert(Number.isFinite(first.stageTimingsMs[stage]) && first.stageTimingsMs[stage] >= 0, stage);
  }
  assert.equal(first.readingCopyReused, false);
  assert.equal(first.title, "Rain and Radio Music");
  assert.equal(await require("./onboardingPreview")._test.generateOnboardingTitle({ storyText: "A radio", profileName: "Alex", storytellerRole: "subject" }), "The old radio");
  assert.equal(first.status, 'imageReady');
  assert.equal(first.refinementModel, 'test-editor');
  assert.equal(first.readingText, 'When I was eight, my dad fixed an old radio.');
  assert.equal(savedMetadata.contentType, 'image/png');
  const cached = await handler(request);
  assert(cached.cached);
  assert.equal(cached.readingText, first.readingText);
  assert.equal(imageCalls, 1);
  await assert.rejects(handler({ ...request, data: { ...request.data, storyText: 'A completely different childhood story.' } }), { code: 'already-exists' });
  await assert.rejects(handler({ ...request, data: { ...request.data, requestId: 'second-preview' } }), { code: 'resource-exhausted' });
  await assert.rejects(handler({ data: request.data }), { code: 'unauthenticated' });

  const jobKey = `users/${uid}/onboardingPreviewJobs/${valid.requestId}`;
  const job = db.records.get(jobKey);
  db.records.set(jobKey, { ...job, status: 'generating', updatedAt: new Date(), attempts: 1 });
  assert.equal((await handler(request)).status, 'generating');
  assert.equal(imageCalls, 1);
  db.records.set(jobKey, { ...job, status: 'failed', attempts: 1, errorCode: 'generation-failed' });
  assert.equal((await handler(request)).status, 'imageReady');
  assert.equal(imageCalls, 2);
  assert.equal(db.records.get(jobKey).attempts, 2);
  assert(db.records.get(jobKey).errorCode.isEqual(admin.firestore.FieldValue.delete()),
    'A successful retry must delete the previous failure code');
  db.records.set(jobKey, { ...job, status: 'failed', attempts: 3 });
  await assert.rejects(handler(request), { code: 'resource-exhausted' });
  assert.equal(imageCalls, 2);
  const untrustedFlagRequest = { ...request, data: { ...request.data, requestId: "untrusted", onboardingPreviewTester: true } };
  await assert.rejects(handler(untrustedFlagRequest), { code: "resource-exhausted" });
  const tester = { auth: { uid, token: { onboardingPreviewTester: true } }, data: { ...request.data, requestId: "tester-second" } };
  assert.equal((await handler(tester)).status, "imageReady");
  const usageKey = `users/${uid}/aiUsage/onboarding_preview_lifetime`;
  assert.equal(db.records.get(usageKey).reserved, 2);
  assert.equal(db.records.get(usageKey).limit, 50);
  db.records.set(usageKey, { reserved: 50 });
  await assert.rejects(handler({ ...tester, data: { ...tester.data, requestId: "tester-over-cap" } }), { code: "resource-exhausted" });
  const { loadOwnedReadingCopy } = require("./onboardingPreview")._test;
  const { TRANSCRIPTION_REFINEMENT_VERSION } = require("./transcriptReadingCopy");
  const input = sanitizeOnboardingPreviewRequest(request.data, uid);
  const copyDb = fakeDatabase();
  const memoryKey = `users/${uid}/memories/${valid.memoryId.toUpperCase()}`;
  const canonical = {
    profileID: valid.profileId.toUpperCase(),
    transcriptionStatus: "completed",
    transcriptionRefinementVersion: TRANSCRIPTION_REFINEMENT_VERSION,
    transcriptionRefinementModel: "gpt-5-mini",
    transcription: input.storyText.replace("my dad", "my\n dad")
  };
  const read = () => loadOwnedReadingCopy({ db: copyDb, userId: uid, input });
  assert.equal(await read(), null, "Typed memory with no server transcript falls back");
  copyDb.records.set(memoryKey.replace(uid, "other-user"), canonical);
  assert.equal(await read(), null, "Never search another user's memory");
  copyDb.records.set(memoryKey, canonical);
  assert.deepEqual(await read(), { text: canonical.transcription, model: "gpt-5-mini" });
  for (const change of [
    { profileID: "other-profile" }, { transcriptionStatus: "processing" },
    { transcriptionRefinementVersion: 1 }, { transcriptionRefinementVersion: 999 },
    { transcription: "An edited typed memory." }, { transcriptionEdited: "Narrator changed this." }
  ]) {
    copyDb.records.set(memoryKey, { ...canonical, ...change });
    assert.equal(await read(), null, JSON.stringify(change));
  }
  copyDb.records.set(memoryKey, { ...canonical, transcriptionEdited: input.storyText });
  assert.equal((await read()).model, "narrator-edit");
  copyDb.records.set(memoryKey, canonical);
  let refinementCalls = 0;
  const reuseHandler = createOnboardingPreviewHandler({
    db: copyDb, bucket: { file: () => ({ save: async () => {} }) }, geminiApiKey: "test",
    generateTitle: async () => "Radio",
    refineStory: async () => { refinementCalls++; return { text: input.storyText, model: "test" }; },
    generateImage: async () => Buffer.from("89504e470d0a1a0a", "hex")
  });
  const reuseResult = await reuseHandler(request);
  assert.equal(reuseResult.readingCopyReused, true);
  assert.equal(refinementCalls, 0, "Matching completed transcript must not call the editor twice");
  assert.equal(reuseResult.readingText, canonical.transcription);
  copyDb.records.set(`users/${uid}/memories/${valid.memoryId}`, canonical);
  assert.equal(await read(), null, "Conflicting legacy document casing falls back safely");
  const concurrentDb = fakeDatabase();
  const originalCollection = concurrentDb.collection;
  let releaseLookup;
  const lookupGate = new Promise(resolve => { releaseLookup = resolve; });
  concurrentDb.collection = name => {
    const collection = originalCollection(name);
    if (name !== "users") return collection;
    return { doc: id => {
      const user = collection.doc(id);
      const originalSubcollection = user.collection;
      user.collection = subcollection => {
        if (subcollection !== "memories") return originalSubcollection(subcollection);
        return { doc: () => ({ get: async () => { await lookupGate; return { exists: false }; } }) };
      };
      return user;
    } };
  };
  let concurrentTitleStarted = false;
  const concurrentHandler = createOnboardingPreviewHandler({
    db: concurrentDb, bucket: { file: () => ({ save: async () => {} }) }, geminiApiKey: "test",
    generateTitle: async () => { concurrentTitleStarted = true; return "Radio"; },
    refineStory: async () => { throw new Error("Editor unavailable"); },
    generateImage: async () => {
      assert(concurrentTitleStarted);
      releaseLookup();
      return Buffer.from("89504e470d0a1a0a", "hex");
    }
  });
  const concurrentResult = await concurrentHandler(request);
  assert.equal(concurrentResult.refinementModel, "deterministic-fallback");
  assert.equal(concurrentResult.readingText, input.storyText);
  const fastHandler = createOnboardingPreviewHandler({
    db: fakeDatabase(),
    bucket: { file: () => ({ save: async () => {} }) },
    geminiApiKey: "test",
    generateTitle: async () => "A childhood memory",
    refineStory: async () => ({ text: input.storyText, model: "test" }),
    generateImage: async (key, prompt, size, references, options) => {
      assert.equal(options.model, "gemini-3.1-flash-lite-image");
      assert.deepEqual(options.responseModalities, ["TEXT", "IMAGE"]);
      assert(references[0].length < 200000, "Fast style anchor must stay small");
      assert.equal(references[0].readUInt16BE(0), 0xffd8);
      assert.match(prompt, /warm watercolor palette/);
      assert.match(prompt, /more cartoon-like/);
      assert(prompt.includes(input.storyText));
      return Buffer.from("89504e470d0a1a0a", "hex");
    }
  });
  const fastResult = await fastHandler({ ...request, auth: { uid, token: { onboardingPreviewTester: true } } });
  assert.equal(fastResult.status, "imageReady");
  console.log('onboarding handler integration tests passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

// SecretParam.value reads this.name; passing the method alone loses its receiver.
{
  const { secretReader } = require("./onboardingPreview")._test;
  const secret = { value() { return this.token; }, token: "test-only-provider-value" };
  assert.strictEqual(secretReader(secret)(), "test-only-provider-value");
}

{
  const { ONBOARDING_TITLE_WINDOW_MS } = require("./onboardingPreview")._test;
  const { openAITextRequestOptions } = require("./storybookAI");
  const now = 1_000_000;
  assert.equal(openAITextRequestOptions(now + ONBOARDING_TITLE_WINDOW_MS, now).timeout, 15_000,
    "Title generation must have a usable provider budget after the shared persistence reserve");
}
