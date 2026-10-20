"use strict";
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { extractOnboardingAppearance, checkOnboardingIllustration } = require("./onboardingVisualChecks");
const bytes = Buffer.from("test-fixture");
const options = { enabled: true, apiKey: "test", image: bytes, portrait: bytes, storyText: "When I was eight my dad fixed the radio.", profileName: "Alex" };
const reply = (value, finishReason = "STOP") => async () => ({ ok: true, json: async () => ({ candidates: [{ finishReason, content: { parts: [{ text: JSON.stringify(value) }] } }] }) });
test("descriptor is bounded, multimodal, JSON and makes one request", async () => {
  let count = 0;
  const result = await extractOnboardingAppearance({ ...options, fetchImpl: async (url, init) => {
    count += 1;
    assert.match(url, /gemini-3\.1-flash-lite:generateContent$/);
    const body = JSON.parse(init.body);
    assert.equal(body.contents[0].parts[1].inlineData.data, bytes.toString("base64"));
    assert.match(body.contents[0].parts[0].text, /Do not infer ethnicity/);
    assert.equal(body.generationConfig.responseMimeType, "application/json");
    assert.ok(init.signal);
    return reply({ description: "Warm brown skin, rounded nose and full lips." })();
  } });
  assert.equal(count, 1);
  assert.match(result.description, /brown/);
});
test("descriptor rejects malformed output and disabled experiment", async () => {
  await assert.rejects(extractOnboardingAppearance({ ...options, fetchImpl: reply({ description: "" }) }));
  await assert.rejects(extractOnboardingAppearance({ ...options, enabled: false }));
});
test("gate accepts a complete positive verdict", async () => {
  assert.deepEqual(await checkOnboardingIllustration({ ...options, fetchImpl: reply({ accepted: true, issues: [] }) }), { accepted: true, issues: [] });
});
test("gate retains concrete rejection", async () => {
  assert.deepEqual(await checkOnboardingIllustration({ ...options, fetchImpl: reply({ accepted: false, issues: ["wrong_age_or_role", "multiple_panels"] }) }), { accepted: false, issues: ["wrong_age_or_role", "multiple_panels"] });
});
test("gate fails closed for inconsistent or malformed judgments", async () => {
  for (const verdict of [{ accepted: true, issues: ["multiple_panels"] }, { accepted: false, issues: [] }, { accepted: "true", issues: [] }, { accepted: true, issues: [], extra: 1 }, { accepted: false, issues: ["invented-code"] }]) {
    assert.equal((await checkOnboardingIllustration({ ...options, fetchImpl: reply(verdict) })).accepted, false);
  }
});
test("gate fails closed on truncation, network failure and disabled experiment without retries", async () => {
  assert.equal((await checkOnboardingIllustration({ ...options, fetchImpl: reply({ accepted: true, issues: [] }, "MAX_TOKENS") })).accepted, false);
  let calls = 0;
  const result = await checkOnboardingIllustration({ ...options, fetchImpl: async () => { calls += 1; throw new Error("timeout"); } });
  assert.deepEqual(result, { accepted: false, issues: ["unavailable"] });
  assert.equal(calls, 1);
  assert.equal((await checkOnboardingIllustration({ ...options, enabled: false })).accepted, false);
});
