"use strict";

/**
 * Max times the cover-url precondition can fail per book before we mark the version failed
 * (stops render-churn; client can still run manual cover regen from the app).
 */
const COVER_PRECONDITION_MAX_ATTEMPTS = 8;
const PDF_MAX_PAGE_COUNT = 800;
const PDF_MIN_DIMENSION_POINTS = 72;
const PDF_MAX_DIMENSION_POINTS = 2000;
const PDF_MAX_PAGE_SOURCE_BYTES = 32 * 1024 * 1024;
const PDF_MAX_TOTAL_SOURCE_BYTES = 512 * 1024 * 1024;
const PDF_MAX_PNG_DIMENSION_PIXELS = 8000;
const PDF_MAX_PNG_PIXELS = 40_000_000;
const PDF_RENDER_LEASE_MILLIS = 6 * 60 * 1000;

class PdfPackagingValidationError extends Error {
  constructor(message, httpStatus = 400) {
    super(message);
    this.name = "PdfPackagingValidationError";
    this.httpStatus = httpStatus;
  }
}

function assertSafeStorageSegment(value, label) {
  const segment = String(value || "");
  if (
    !segment ||
    segment.length > 128 ||
    segment === "." ||
    segment === ".." ||
    /[\\/\x00-\x1f\x7f]/.test(segment)
  ) {
    throw new PdfPackagingValidationError(`${label} is not a safe storage path segment.`);
  }
  return segment;
}

function validatePageDimensions(record) {
  const width = Number(record?.pageWidth ?? 612);
  const height = Number(record?.pageHeight ?? 792);
  for (const [label, value] of [["pageWidth", width], ["pageHeight", height]]) {
    if (
      !Number.isFinite(value) ||
      value < PDF_MIN_DIMENSION_POINTS ||
      value > PDF_MAX_DIMENSION_POINTS
    ) {
      throw new PdfPackagingValidationError(
        `${label} must be between ${PDF_MIN_DIMENSION_POINTS} and ${PDF_MAX_DIMENSION_POINTS} points.`
      );
    }
  }
  return { trimWidthPt: width, trimHeightPt: height };
}

/**
 * Validates the complete client-authored render manifest before Storage is touched.
 * Only the canonical print-master PNG for each page is accepted.
 */
function validatePdfPackagingManifest({ userId, bookVersionId, record }) {
  const safeUserId = assertSafeStorageSegment(userId, "userId");
  const safeBookVersionId = assertSafeStorageSegment(bookVersionId, "bookVersionId");
  const pages = Array.isArray(record?.pages) ? [...record.pages] : [];
  if (!pages.length) {
    throw new PdfPackagingValidationError("No pages available for PDF packaging.");
  }
  if (pages.length > PDF_MAX_PAGE_COUNT) {
    throw new PdfPackagingValidationError(
      `PDF packaging supports at most ${PDF_MAX_PAGE_COUNT} pages.`,
      413
    );
  }

  const dimensions = validatePageDimensions(record);
  pages.sort((a, b) => Number(a?.pageIndex) - Number(b?.pageIndex));
  const seenIndexes = new Set();
  const validatedPages = pages.map((page, position) => {
    const pageIndex = Number(page?.pageIndex);
    if (!Number.isSafeInteger(pageIndex) || pageIndex < 0 || pageIndex >= PDF_MAX_PAGE_COUNT) {
      throw new PdfPackagingValidationError(`Invalid pageIndex at position ${position}.`);
    }
    if (seenIndexes.has(pageIndex)) {
      throw new PdfPackagingValidationError(`Duplicate pageIndex ${pageIndex}.`);
    }
    seenIndexes.add(pageIndex);

    const pageFile = `page_${String(pageIndex).padStart(3, "0")}.png`;
    const expectedPath = `users/${safeUserId}/bookVersions/${safeBookVersionId}/pages/${pageFile}`;
    const storagePath = String(page?.renderedPageStoragePath || "").trim();
    if (storagePath !== expectedPath) {
      throw new PdfPackagingValidationError(
        `Page ${pageIndex} must use its canonical print-master PNG path.`
      );
    }
    return { pageIndex, storagePath };
  });

  return { ...dimensions, pages: validatedPages };
}

function validatePngPageMetadata(metadata, pageIndex) {
  const contentType = String(metadata?.contentType || "").split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "image/png") {
    throw new PdfPackagingValidationError(`Page ${pageIndex} is not an image/png object.`, 413);
  }
  const size = Number(metadata?.size);
  if (!Number.isSafeInteger(size) || size <= 0 || size > PDF_MAX_PAGE_SOURCE_BYTES) {
    throw new PdfPackagingValidationError(
      `Page ${pageIndex} exceeds the ${PDF_MAX_PAGE_SOURCE_BYTES}-byte source limit.`,
      413
    );
  }
  const generation = String(metadata?.generation || "").trim();
  if (!generation) {
    throw new PdfPackagingValidationError(`Page ${pageIndex} metadata has no object generation.`, 409);
  }
  return { size, generation };
}

function validatePdfSourceMetadata(pages, metadataList) {
  if (!Array.isArray(metadataList) || metadataList.length !== pages.length) {
    throw new PdfPackagingValidationError("Page metadata preflight was incomplete.", 500);
  }
  let totalSourceBytes = 0;
  const generations = [];
  const sourceSizes = metadataList.map((metadata, index) => {
    const { size, generation } = validatePngPageMetadata(metadata, pages[index].pageIndex);
    generations.push(generation);
    totalSourceBytes += size;
    if (totalSourceBytes > PDF_MAX_TOTAL_SOURCE_BYTES) {
      throw new PdfPackagingValidationError(
        `PDF page sources exceed the ${PDF_MAX_TOTAL_SOURCE_BYTES}-byte cumulative limit.`,
        413
      );
    }
    return size;
  });
  return { sourceSizes, generations, totalSourceBytes };
}

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return Number(value.toMillis()) || 0;
  if (value && Number.isFinite(Number(value._seconds))) return Number(value._seconds) * 1000;
  if (value instanceof Date) return value.getTime();
  return Number(value) || 0;
}

function pdfRenderLeaseDecision(record, { forceRegenerate = false, nowMillis = Date.now(), lease = null } = {}) {
  const leaseExpiresAt = timestampMillis(lease?.expiresAt);
  if (
    lease?.status === "rendering" &&
    typeof lease?.renderJobId === "string" &&
    lease.renderJobId &&
    leaseExpiresAt > nowMillis
  ) {
    return { action: "in-progress", leaseExpiresAt };
  }
  if (record?.renderStatus === "rendered" && record?.pdfURL) {
    return { action: forceRegenerate ? "force-denied" : "cached" };
  }
  return { action: "claim" };
}

function hasPngSignature(bytes) {
  if (!bytes || bytes.length < 8) return false;
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  return signature.every((value, index) => bytes[index] === value);
}

function validatePngHeader(bytes, pageIndex) {
  if (!hasPngSignature(bytes) || bytes.length < 24 || bytes.toString("ascii", 12, 16) !== "IHDR") {
    throw new PdfPackagingValidationError(`Page ${pageIndex} does not contain valid PNG header data.`, 413);
  }
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  if (
    width <= 0 ||
    height <= 0 ||
    width > PDF_MAX_PNG_DIMENSION_PIXELS ||
    height > PDF_MAX_PNG_DIMENSION_PIXELS ||
    width * height > PDF_MAX_PNG_PIXELS
  ) {
    throw new PdfPackagingValidationError(`Page ${pageIndex} PNG dimensions are too large.`, 413);
  }
  return { width, height };
}

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
  COVER_PRECONDITION_EXHAUSTED_STATUS,
  PDF_MAX_PAGE_COUNT,
  PDF_MAX_PAGE_SOURCE_BYTES,
  PDF_MAX_TOTAL_SOURCE_BYTES,
  PDF_RENDER_LEASE_MILLIS,
  PdfPackagingValidationError,
  validatePdfPackagingManifest,
  validatePdfSourceMetadata,
  pdfRenderLeaseDecision,
  hasPngSignature,
  validatePngHeader
};
