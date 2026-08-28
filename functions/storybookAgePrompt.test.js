const test = require("node:test");
const assert = require("node:assert/strict");
const {
  assembleFinalPrompt,
  createStorybookAI,
  explicitAge
} = require("./storybookAI");

test("parses compound English ages without matching the trailing unit", () => {
  assert.equal(explicitAge("I was twenty-two in 1986 when I learned to braid dough."), 22);
  assert.equal(explicitAge("I was twenty two in 1986 when I learned to braid dough."), 22);
  assert.equal(explicitAge("When I was seventy-five, I moved closer to family."), 75);
  assert.equal(explicitAge("I was forty when the shop opened."), 40);
});

test("preserves existing numeric and simple-word age parsing", () => {
  assert.equal(explicitAge("At forty-one, I enrolled in woodworking class."), 41);
  assert.equal(explicitAge("When I was eight, I rode to the market."), 8);
  assert.equal(explicitAge("I was 22 when I learned to bake."), 22);
});

test("places a final page-age lock after conflicting present-day profile cues", () => {
  const prompt = assembleFinalPrompt(
    "At forty-one, after years behind a desk, I enrolled in woodworking class.",
    "Character 1: Daniel Reed - narrator",
    "likelyPresent",
    "Daniel Reed stands in a woodworking shop.",
    "kidsBook",
    "",
    true,
    {
      profileName: "Daniel Reed",
      faceDescription: "Older adult man with gray hair and wrinkles",
      profileEthnicity: "Mediterranean American",
      gender: "Man",
      otherDetails: "Retired storyteller"
    },
    "normal",
    { referenceImageOrder: ["headshot"], characterDetailsForAge: "" }
  );

  assert.match(prompt, /FINAL NARRATOR AGE LOCK[^\n]*age 41/);
  assert.ok(prompt.lastIndexOf("FINAL NARRATOR AGE LOCK") > prompt.lastIndexOf("Older adult"));
  assert.match(prompt, /Do not copy present-day gray hair, wrinkles, beard color/);
});

test("explicit historical age overrides the narrator profile card age", () => {
  const prompt = assembleFinalPrompt(
    "I was twenty-two when I opened the bakery.",
    "Character 1: Daniel Reed - memoir narrator",
    "likelyPresent",
    "Daniel Reed opens the bakery door.",
    "kidsBook",
    "",
    true,
    { profileName: "Daniel Reed" },
    "normal",
    {
      referenceImageOrder: ["headshot"],
      characterDetailsForAge: JSON.stringify({
        characters: [
          { id: "__narrator__", age: "72", isSynthesizedNarrator: true }
        ]
      })
    }
  );

  assert.match(prompt, /FINAL NARRATOR AGE LOCK[^\n]*age 22/);
  assert.doesNotMatch(prompt, /FINAL NARRATOR AGE LOCK[^\n]*age 72/);
});

test("older-adult age labels use a grammatical article", () => {
  const prompt = assembleFinalPrompt(
    "At sixty-six, I retired from the library.",
    "Character 1: Daniel Reed - memoir narrator",
    "likelyPresent",
    "Daniel Reed leaves the library.",
    "kidsBook",
    "",
    false,
    { profileName: "Daniel Reed" },
    "normal",
    {}
  );

  assert.match(prompt, /reading as an older adult/);
  assert.doesNotMatch(prompt, /reading as a elderly/);
});

test("exposes pitch-quality guards through the worker AI facade", () => {
  const ai = createStorybookAI("test-openai-key", "test-gemini-key");
  assert.equal(typeof ai.isUsableBackCoverPitch, "function");
  assert.equal(typeof ai.fallbackBackCoverPitch, "function");
});

test("locks singular props to one coherent instant", () => {
  const prompt = assembleFinalPrompt(
    "Mara sat on the small oak bench I built.",
    "Character 1: Daniel Reed - memoir narrator; Character 2: Mara - spouse",
    "likelyPresent",
    "Daniel holds the oak bench while Mara sits on the bench.",
    "kidsBook",
    "",
    false,
    { profileName: "Daniel Reed" },
    "normal",
    {}
  );

  assert.match(prompt, /Singular-object lock/);
  assert.match(prompt, /render exactly one object/);
});
