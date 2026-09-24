const test = require("node:test");
const assert = require("node:assert/strict");
const { chapterMemories } = require("./storybookMemorySelection");

test("keeps only memories assigned to a chapter", () => {
  const memories = [
    { id: "chapter-1", chapter: "Childhood" },
    { id: "blank", chapter: "   " },
    { id: "missing" },
    { id: "null", chapter: null },
    { id: "chapter-2", chapter: " Family " }
  ];

  assert.deepEqual(
    chapterMemories(memories).map((memory) => memory.id),
    ["chapter-1", "chapter-2"]
  );
});

test("returns an empty list for invalid input", () => {
  assert.deepEqual(chapterMemories(null), []);
  assert.deepEqual(chapterMemories({}), []);
});

test("restricts a new job to its explicitly pinned memoir memories", () => {
  const memories = [
    { id: "life", chapter: "Beginnings" },
    { id: "parent", chapter: "Before They Came" },
    { id: "love", chapter: "First Glimpse" }
  ];

  assert.deepEqual(
    chapterMemories(memories, ["parent"]).map((memory) => memory.id),
    ["parent"]
  );
});

test("ignores invalid pin collections without breaking legacy jobs", () => {
  const memories = [{ id: "life", chapter: "Beginnings" }];
  assert.deepEqual(chapterMemories(memories, "life"), memories);
});
