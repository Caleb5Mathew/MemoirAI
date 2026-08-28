const MAX_RETRY_SLEEP_MS = 45_000;
const DEADLINE_RESERVE_MS = 10_000;

function boundedRetryDelayMs({
  baseDelayMs,
  serverDelayMs,
  jitterFraction,
  nowMs,
  deadlineMs
}) {
  const remainingMs = deadlineMs - nowMs - DEADLINE_RESERVE_MS;
  if (remainingMs <= 0) return null;
  const requestedMs = Math.max(Number(baseDelayMs) || 0, Number(serverDelayMs) || 0);
  const jitterMs = Math.max(0, requestedMs * Math.max(0, Number(jitterFraction) || 0));
  return Math.max(0, Math.floor(Math.min(
    requestedMs + jitterMs,
    MAX_RETRY_SLEEP_MS,
    remainingMs
  )));
}

module.exports = {
  DEADLINE_RESERVE_MS,
  MAX_RETRY_SLEEP_MS,
  boundedRetryDelayMs
};
