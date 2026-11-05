const STORIES_PER_WORKER_BATCH = 6;
const MAX_EMPTY_BATCHES = 3;

function planStorybookBatch(orderedMemoryIds, results = {}, failures = {}) {
  if (!Array.isArray(orderedMemoryIds) || !orderedMemoryIds.length ||
      orderedMemoryIds.some(id => typeof id !== "string" || !id) ||
      new Set(orderedMemoryIds).size !== orderedMemoryIds.length) {
    throw new Error("A book needs distinct ordered memory identifiers.");
  }
  const pending = orderedMemoryIds.filter(id =>
    !results[id]?.illustrationStoragePath && !failures[id]
  );
  return {
    pending,
    batchIds: pending.slice(0, STORIES_PER_WORKER_BATCH),
    completedCount: orderedMemoryIds.length - pending.length
  };
}

function continuationDecision({ remainingCount, previousCompleted, completedCount,
  emptyBatchCount = 0, continuationCount = 0, totalCount }) {
  if (remainingCount === 0) return { action: "finish" };
  const emptyCount = completedCount > previousCompleted ? 0 : emptyBatchCount + 1;
  const nextCount = continuationCount + 1;
  const maximumContinuations = Math.ceil(totalCount / STORIES_PER_WORKER_BATCH) * 3 + 3;
  if (emptyCount >= MAX_EMPTY_BATCHES || nextCount > maximumContinuations) {
    return { action: "fail", message: "Book generation could not make further progress. Your saved stories are safe. Please try again." };
  }
  return { action: "continue", emptyBatchCount: emptyCount, continuationCount: nextCount };
}

function shouldContinueStorybookEvent(before, after) {
  return after?.status === "running_continue" && before?.status !== "running_continue";
}

module.exports = { STORIES_PER_WORKER_BATCH, MAX_EMPTY_BATCHES,
  planStorybookBatch, continuationDecision, shouldContinueStorybookEvent };
