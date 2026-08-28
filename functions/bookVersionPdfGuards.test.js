"use strict";

const assert = require("assert");
const {
  mustAbortPdfPackagingForMissingCoverUrl,
  nextCoverPreconditionAttemptMeta,
  COVER_PRECONDITION_MAX_ATTEMPTS,
  PDF_MAX_PAGE_COUNT,
  PDF_MAX_PAGE_SOURCE_BYTES,
  PDF_MAX_TOTAL_SOURCE_BYTES,
  validatePdfPackagingManifest,
  validatePdfSourceMetadata,
  pdfRenderLeaseDecision,
  hasPngSignature,
  validatePngHeader
} = require("./bookVersionPdfGuards");

function page(index, overrides = {}) {
  return {
    pageIndex: index,
    renderedPageStoragePath: `users/user-a/bookVersions/book-a/pages/page_${String(index).padStart(3, "0")}.png`,
    ...overrides
  };
}

function manifest(overrides = {}) {
  const { record: recordOverrides = {}, ...topLevelOverrides } = overrides;
  return {
    userId: "user-a",
    bookVersionId: "book-a",
    ...topLevelOverrides,
    record: {
      pageWidth: 612,
      pageHeight: 792,
      pages: [page(0), page(1)],
      ...recordOverrides
    }
  };
}

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

// Canonical tenant-bound print-master paths are accepted and sorted.
{
  const result = validatePdfPackagingManifest(manifest({
    record: { pages: [page(1), page(0)] }
  }));
  assert.deepStrictEqual(result.pages.map((p) => p.pageIndex), [0, 1]);
  assert.strictEqual(result.trimWidthPt, 612);
}

// Foreign tenants, arbitrary filenames, traversal, and delivery JPEGs are rejected.
{
  const unsafePaths = [
    "users/user-b/bookVersions/book-a/pages/page_000.png",
    "users/user-a/bookVersions/book-a/pages/../page_000.png",
    "users/user-a/bookVersions/book-a/pages/not-a-page.png",
    "users/user-a/bookVersions/book-a/pages/page_000.jpg"
  ];
  for (const renderedPageStoragePath of unsafePaths) {
    assert.throws(() => validatePdfPackagingManifest(manifest({
      record: { pages: [page(0, { renderedPageStoragePath })] }
    })), /canonical print-master PNG path/);
  }
  assert.throws(() => validatePdfPackagingManifest(manifest({
    record: { pages: [page(0, { renderedPageStoragePath: null, imageStoragePath: "users/user-a/bookVersions/book-a/pages/page_000.jpg" })] }
  })), /canonical print-master PNG path/);
  assert.throws(
    () => validatePdfPackagingManifest(manifest({ bookVersionId: "../book-a" })),
    /safe storage path segment/
  );
}

// Manifest size and dimensions are bounded before Storage work begins.
{
  const tooManyPages = Array.from({ length: PDF_MAX_PAGE_COUNT + 1 }, (_, index) => page(index));
  assert.throws(
    () => validatePdfPackagingManifest(manifest({ record: { pages: tooManyPages } })),
    /at most 800 pages/
  );
  for (const badWidth of [0, -1, Infinity, NaN, 2001]) {
    assert.throws(
      () => validatePdfPackagingManifest(manifest({ record: { pageWidth: badWidth } })),
      /pageWidth must be between/
    );
  }
  assert.throws(
    () => validatePdfPackagingManifest(manifest({ record: { pageHeight: 10 } })),
    /pageHeight must be between/
  );
}

// Metadata type, per-page bytes, and cumulative bytes are checked in preflight.
{
  const pages = [page(0), page(1)];
  assert.deepStrictEqual(
    validatePdfSourceMetadata(pages, [
      { contentType: "image/png", size: "100", generation: "11" },
      { contentType: "image/png; charset=binary", size: 200, generation: "12" }
    ]),
    { sourceSizes: [100, 200], generations: ["11", "12"], totalSourceBytes: 300 }
  );
  assert.throws(
    () => validatePdfSourceMetadata([page(0)], [{ contentType: "image/jpeg", size: 100, generation: "1" }]),
    /not an image\/png/
  );
  assert.throws(
    () => validatePdfSourceMetadata([page(0)], [{ contentType: "image/png", size: PDF_MAX_PAGE_SOURCE_BYTES + 1, generation: "1" }]),
    /source limit/
  );
  const cumulativePages = Array.from({ length: 17 }, (_, index) => page(index));
  assert(PDF_MAX_PAGE_SOURCE_BYTES * cumulativePages.length > PDF_MAX_TOTAL_SOURCE_BYTES);
  assert.throws(
    () => validatePdfSourceMetadata(
      cumulativePages,
      cumulativePages.map((_, index) => ({ contentType: "image/png", size: PDF_MAX_PAGE_SOURCE_BYTES, generation: String(index + 1) }))
    ),
    /cumulative limit/
  );
}

// An active lease is idempotent; rendered output cannot be force-regenerated by clients.
{
  const now = 1_000_000;
  assert.strictEqual(pdfRenderLeaseDecision({}, { nowMillis: now, lease: {
    status: "rendering",
    renderJobId: "job-a",
    expiresAt: now + 1000
  } }).action, "in-progress");
  assert.strictEqual(pdfRenderLeaseDecision({}, { nowMillis: now, lease: {
    status: "rendering",
    renderJobId: "job-a",
    expiresAt: now - 1
  } }).action, "claim");
  assert.strictEqual(pdfRenderLeaseDecision({ renderStatus: "rendered", pdfURL: "https://example/pdf" }).action, "cached");
  assert.strictEqual(pdfRenderLeaseDecision(
    { renderStatus: "rendered", pdfURL: "https://example/pdf" },
    { forceRegenerate: true }
  ).action, "force-denied");
}

{
  assert.strictEqual(hasPngSignature(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), true);
  assert.strictEqual(hasPngSignature(Buffer.from("not png")), false);
  const header = Buffer.alloc(24);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(header);
  header.write("IHDR", 12, "ascii");
  header.writeUInt32BE(2550, 16);
  header.writeUInt32BE(3300, 20);
  assert.deepStrictEqual(validatePngHeader(header, 0), { width: 2550, height: 3300 });
  header.writeUInt32BE(100_000, 16);
  assert.throws(() => validatePngHeader(header, 0), /dimensions are too large/);
}

console.log("bookVersionPdfGuards: ok");
