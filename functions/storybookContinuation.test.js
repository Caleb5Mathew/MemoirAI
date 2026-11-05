const assert = require("assert");
const { planStorybookBatch, continuationDecision, shouldContinueStorybookEvent,
  STORIES_PER_WORKER_BATCH } = require("./storybookContinuation");

const ids = Array.from({ length: 40 }, (_, i) => `memory-${i}`);
const results = {};
const calls = [];
let batches = 0;
while (true) {
  const plan = planStorybookBatch(ids, results);
  if (!plan.pending.length) break;
  assert(plan.batchIds.length <= STORIES_PER_WORKER_BATCH);
  for (const id of plan.batchIds) {
    calls.push(id);
    results[id] = { illustrationStoragePath: `generated/${id}.png` };
  }
  batches++;
}
assert.strictEqual(batches, 7);
assert.deepStrictEqual(calls, ids);
assert.strictEqual(new Set(calls).size, 40);
assert.deepStrictEqual(planStorybookBatch(ids, results).batchIds, []);
assert.throws(() => planStorybookBatch(["same", "same"]));
assert.throws(() => planStorybookBatch([]));
const resumed = planStorybookBatch(ids, { [ids[0]]: results[ids[0]] }, { [ids[1]]: { stage: "image" } });
assert.strictEqual(resumed.completedCount, 2);
assert.strictEqual(resumed.batchIds[0], ids[2]);
assert.deepStrictEqual(continuationDecision({ remainingCount: 0 }), { action: "finish" });
assert.strictEqual(continuationDecision({ remainingCount: 2, previousCompleted: 0,
  completedCount: 0, emptyBatchCount: 2, totalCount: 2 }).action, "fail");
assert.deepStrictEqual(continuationDecision({ remainingCount: 34, previousCompleted: 0,
  completedCount: 6, emptyBatchCount: 2, totalCount: 40 }),
  { action: "continue", emptyBatchCount: 0, continuationCount: 1 });
assert.strictEqual(continuationDecision({ remainingCount: 1, previousCompleted: 0,
  completedCount: 1, continuationCount: 100, totalCount: 40 }).action, "fail");
assert(shouldContinueStorybookEvent({ status: "running" }, { status: "running_continue" }));
assert(!shouldContinueStorybookEvent({ status: "running_continue" }, { status: "running_continue" }));
assert(!shouldContinueStorybookEvent({ status: "running" }, { status: "aiComplete" }));
console.log("storybook continuation tests passed: forty stories, resume, bounded failure, event deduplication");
