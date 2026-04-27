"use strict";

const assert = require("assert");
const {
  mustAbortPdfPackagingForMissingCoverUrl,
  nextCoverPreconditionAttemptMeta,
  COVER_PRECONDITION_MAX_ATTEMPTS
} = require("./bookVersionPdfGuards");

{
  assert.strictEqual(mustAbortPdfPackagingForMissingCoverUrl({ coverURL: "" }), true);
  assert.strictEqual(mustAbortPdfPackagingForMissingCoverUrl({ coverURL: "   " }), true);
  assert.strictEqual(mustAbortPdfPackagingForMissingCoverUrl({ coverURL: null }), true);
  assert.strictEqual(mustAbortPdfPackagingForMissingCoverUrl({ coverURL: "https://x/ok.pdf" }), false);
  assert.strictEqual(
    mustAbortPdfPackagingForMissingCoverUrl({ coverURL: "  https://x/ok.pdf " }),
    false
  );
}

// Cap: one before max is not exhausted; at max, next attempt is exhausted
{
  const m1 = nextCoverPreconditionAttemptMeta({ renderAttemptCount: COVER_PRECONDITION_MAX_ATTEMPTS - 1 });
  assert.strictEqual(m1.exhausted, false);
  assert.strictEqual(m1.nextCount, COVER_PRECONDITION_MAX_ATTEMPTS);
  const m2 = nextCoverPreconditionAttemptMeta({ renderAttemptCount: COVER_PRECONDITION_MAX_ATTEMPTS });
  assert.strictEqual(m2.exhausted, true);
  assert.strictEqual(m2.nextCount, COVER_PRECONDITION_MAX_ATTEMPTS + 1);
}

console.log("bookVersionPdfGuards: ok");
