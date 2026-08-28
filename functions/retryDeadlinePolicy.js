const MAX_RETRY_SLEEP_MS = 45_000;
const DEADLINE_RESERVE_MS = 10_000;
const PROVIDER_PERSIST_RESERVE_MS = 30_000;

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

function boundedProviderRequestTimeoutMs({
  maximumTimeoutMs,
  nowMs,
  deadlineMs,
  persistReserveMs = PROVIDER_PERSIST_RESERVE_MS
}) {
  const remainingMs = Number(deadlineMs) - Number(nowMs) - Math.max(0, Number(persistReserveMs) || 0);
  if (!Number.isFinite(remainingMs) || remainingMs < 1_000) return null;
  return Math.max(1_000, Math.floor(Math.min(
    Math.max(1_000, Number(maximumTimeoutMs) || 1_000),
    remainingMs
  )));
}

function canStartProviderAttempt({ nowMs, deadlineMs, minimumExecutionMs }) {
  const neededMs = Math.max(0, Number(minimumExecutionMs) || 0) + PROVIDER_PERSIST_RESERVE_MS;
  return Number(deadlineMs) - Number(nowMs) >= neededMs;
}

function isRetryableProviderError(error) {
  const status = Number(error?.status || error?.statusCode || error?.response?.status || 0);
  if ([429, 500, 502, 503, 504].includes(status)) return true;
  const code = String(error?.code || error?.cause?.code || "").toUpperCase();
  if (["ECONNRESET", "EAI_AGAIN", "ENETUNREACH", "ECONNREFUSED"].includes(code)) return true;
  const message = String(error?.message || "").toUpperCase();
  return message.includes("RESOURCE_EXHAUSTED") || message.includes("HTTP 429");
}

module.exports = {
  DEADLINE_RESERVE_MS,
  MAX_RETRY_SLEEP_MS,
  PROVIDER_PERSIST_RESERVE_MS,
  boundedRetryDelayMs,
  boundedProviderRequestTimeoutMs,
  canStartProviderAttempt,
  isRetryableProviderError
};
