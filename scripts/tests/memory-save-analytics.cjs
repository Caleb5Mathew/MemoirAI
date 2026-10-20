const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const source = readFileSync(resolve(__dirname, '../../MemoirAI/Memoir/RecordingView.swift'), 'utf8');
const save = source.slice(source.indexOf('func saveMemory()'), source.indexOf('// Helper – writes image data'));

test('Saved Memory is emitted once in the successful durable-save branch', () => {
  const durableSave = save.indexOf('try bgContext.save()');
  const event = save.indexOf('event: "Saved Memory"');
  const failure = save.indexOf('} catch {', durableSave);
  assert.equal(save.split('event: "Saved Memory"').length - 1, 1);
  assert.ok(durableSave >= 0 && event > durableSave && event < failure);
});

test('saved content flags describe the durable entry', () => {
  assert.ok(save.includes('"has_audio": entry.hasAudio'));
  assert.ok(save.includes('"has_text": !(entry.text?.isEmpty ?? true)'));
  assert.ok(save.includes('"has_photos": !(entry.photos?.allObjects.isEmpty ?? true)'));
});
