const crypto = require("node:crypto");

function safeLogIdentifier(value) {
  const normalized = String(value || "").trim();
  if (!normalized) return null;
  return crypto.createHash("sha256").update(normalized).digest("hex").slice(0, 12);
}

function safeErrorMetadata(error) {
  const status = Number(error?.status || error?.statusCode || error?.response?.status || 0);
  return {
    errorName: String(error?.name || "Error").slice(0, 80),
    errorCode: String(error?.code || error?.cause?.code || "unknown").slice(0, 80),
    httpStatus: Number.isFinite(status) && status > 0 ? status : null
  };
}

function privacySafeLogDetails(details) {
  const safe = {};
  for (const [key, value] of Object.entries(details || {})) {
    if (/^(?:user|job|memory|profile)Id$/i.test(key)) {
      safe[`${key}Hash`] = safeLogIdentifier(value);
    } else {
      safe[key] = value;
    }
  }
  return safe;
}

module.exports = {
  privacySafeLogDetails,
  safeErrorMetadata,
  safeLogIdentifier
};
