"use strict";

const assert = require("assert");
const { sharedMemoryProjection } = require("./sharedMemoryProjection");

const projection = sharedMemoryProjection("memory-1", {
  prompt: "Prompt",
  transcription: "Story",
  audioStoragePath: "users/owner/audio/memory-1.m4a",
  audioURL: "https://secret.example/token",
  characterDetails: "private"
}, () => "SERVER_TIME");

assert.deepStrictEqual(projection, {
  memoryId: "memory-1",
  prompt: "Prompt",
  transcription: "Story",
  audioStoragePath: "users/owner/audio/memory-1.m4a",
  updatedAt: "SERVER_TIME"
});
assert.ok(!Object.hasOwn(projection, "audioURL"));
assert.ok(!Object.hasOwn(projection, "characterDetails"));

console.log("sharedMemoryProjection.test.js: all assertions passed");
