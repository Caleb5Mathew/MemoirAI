"use strict";

/**
 * Max times the cover-url precondition can fail per book before we mark the version failed
 * (stops render-churn; client can still run manual cover regen from the app).
 */
const COVER_PRECONDITION_MAX_ATTEMPTS = 8;

/**
 * Shared rule for `generateBookVersionPdf`: do not package when the client has not
 * uploaded a cover yet. Keeps the condition in one place for Cloud Function + unit tests.
 *
 * @param {object} record Firestore `bookVersions` document fields
 * @returns {boolean} true when `coverURL` is missing/blank and packaging must abort with 409
 */
function mustAbortPdfPackagingForMissingCoverUrl(record) {
  return !String((record && record.coverURL) || "").trim();
}

/**
 * @param {object} record
 * @returns {{ exhausted: boolean, nextCount: number }}
 */
function nextCoverPreconditionAttemptMeta(record) {
  const nextCount = (record && record.renderAttemptCount != null ? Number(record.renderAttemptCount) : 0) + 1;
  return {
    exhausted: nextCount > COVER_PRECONDITION_MAX_ATTEMPTS,
    nextCount
  };
}

const COVER_PRECONDITION_EXHAUSTED_STATUS = "cover_precondition_exhausted";

module.exports = {
  COVER_PRECONDITION_MAX_ATTEMPTS,
  mustAbortPdfPackagingForMissingCoverUrl,
  nextCoverPreconditionAttemptMeta,
  COVER_PRECONDITION_EXHAUSTED_STATUS
};
