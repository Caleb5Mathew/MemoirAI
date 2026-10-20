const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const recorder = fs.readFileSync('MemoirAI/Onboarding/OnboardingRecorder.swift', 'utf8');
const creation = fs.readFileSync('MemoirAI/Onboarding/MemoryCreationService.swift', 'utf8');

test('onboarding waits for speech completion and bounds the final-result wait', () => {
  assert.match(recorder, /request\?\.endAudio\(\)/);
  assert.match(recorder, /func finish\(\) async -> String/);
  assert.match(recorder, /while isFinalizing/);
  assert.match(recorder, /2_000_000_000/);
  assert.match(recorder, /result\?\.isFinal == true/);
  assert.match(recorder, /audioRecorderDidFinishRecording/);
});

test('onboarding save preserves original transcript and rejects stale retry payloads', () => {
  assert.match(creation, /entry\.transcriptionRawText = raw/);
  assert.match(creation, /throw MemoryCreationError\.changedStory/);
  assert.match(creation, /context\.delete\(entry\)\s+throw error/);
});

test('QR readiness awaits audio upload and remote playback, scoped to the signed-in owner', () => {
  const sync = creation.slice(creation.indexOf('func syncOnboardingMemory'));
  assert.match(sync, /guard await FirestoreSyncService\.shared\.syncMemory/);
  assert.match(sync, /await FirestoreSyncService\.shared\.freshAudioPlaybackURL/);
  assert.match(sync, /Auth\.auth\(\)\.currentUser\?\.uid == firebaseUserID/);
  assert.match(sync, /throw MemoryCreationError\.cloudSyncFailed/);
});

test('permission replies and failed engine startup cannot leave a hidden recording', () => {
  assert.match(recorder, /self\.permissionRequestID == permissionID/);
  assert.match(recorder, /func stop\(\) -> String \{\s+permissionRequestID = UUID\(\)/);
  assert.match(recorder, /if hasInputTap \{\s+engine\?\.inputNode\.removeTap/);
  const completion = recorder.slice(recorder.indexOf('private func completeFinalization'));
  assert.match(completion, /request\?\.endAudio\(\)/);
  assert.match(completion, /stopAudioEngine\(\)/);
});


test('speech completion never truncates a longer audio recording', () => {
  const callback = recorder.slice(recorder.indexOf('recognitionTask = recognizer.recognitionTask'), recorder.indexOf('engine.inputNode.installTap'));
  assert.doesNotMatch(callback, /self\.stop\(/);
  assert.doesNotMatch(callback, /recorder\?\.stop\(/);
  assert.match(callback, /self\.liveCaptionEnded = true/);
  const completion = recorder.slice(recorder.indexOf('private func completeFinalization'), recorder.indexOf('private func stopAudioEngine'));
  assert.doesNotMatch(completion, /recorder\?\.stop\(/);
  assert.match(completion, /if !isRecording \{\s+try\? AVAudioSession\.sharedInstance\(\)\.setActive\(false\)/);
});
