const assert = require("assert");

const {
  canonicalBookArtifactPaths,
  assertCanonicalBookArtifact,
  assertPdfMetadata,
  checkoutFulfillmentFingerprint,
  ensureBookVersionArtifactUrls,
  validateCheckoutBookArtifacts
} = require("./storageArtifactUrls");

function mockDb(record, writes = []) {
  const ref = {
    async get() {
      return { exists: true, data: () => record };
    },
    async set(data, options) {
      writes.push({ data, options });
    }
  };
  return {
    collection() {
      return {
        doc() {
          return {
            collection() {
              return { doc: () => ref };
            }
          };
        }
      };
    }
  };
}

function mockPdfBucket(paths) {
  return {
    name: "memoirai-test.firebasestorage.app",
    file(path) {
      if (!paths[path]) throw new Error(`Unexpected Storage path: ${path}`);
      return {
        async exists() {
          return [true];
        },
        async getMetadata() {
          return [{
            contentType: paths[path].contentType || "application/pdf",
            size: String(paths[path].size || 1024),
            generation: paths[path].generation || "7",
            metadata: { firebaseStorageDownloadTokens: paths[path].token }
          }];
        },
        async setMetadata() {
          throw new Error("Existing test token should be reused");
        }
      };
    }
  };
}

async function run() {
  const expected = canonicalBookArtifactPaths("owner-1", "book-1");
  assert.deepStrictEqual(expected, {
    cover: "users/owner-1/bookVersions/book-1/cover.pdf",
    interior: "users/owner-1/bookVersions/book-1/book.pdf"
  });
  assert.throws(() => canonicalBookArtifactPaths("victim/uid", "book-1"), /Invalid/);
  assert.strictEqual(
    assertCanonicalBookArtifact(expected.cover, expected.cover, "Cover"),
    expected.cover
  );
  assert.throws(
    () => assertCanonicalBookArtifact("users/victim/audio/memory.m4a", expected.cover, "Cover"),
    /not canonical/
  );
  assert.deepStrictEqual(
    assertPdfMetadata({ contentType: "application/pdf", size: "2048", generation: "7" }, "Cover"),
    { generation: "7", size: 2048 }
  );
  assert.throws(
    () => assertPdfMetadata({ contentType: "audio/mp4", size: "2048", generation: "7" }, "Cover"),
    /not a PDF/
  );
  assert.throws(
    () => assertPdfMetadata({ contentType: "application/pdf", size: "0", generation: "7" }, "Cover"),
    /size/
  );
  assert.throws(
    () => assertPdfMetadata({ contentType: "application/pdf", size: "2048" }, "Cover"),
    /generation/
  );

  let storageWasRead = false;
  const maliciousDb = mockDb({
    coverStoragePath: "users/victim/audio/private.m4a",
    pdfStoragePath: expected.interior
  });
  await assert.rejects(
    ensureBookVersionArtifactUrls(
      maliciousDb,
      { file: () => { storageWasRead = true; throw new Error("must not read"); } },
      "owner-1",
      "book-1"
    ),
    /not canonical/
  );
  assert.strictEqual(storageWasRead, false, "cross-tenant path must fail before Admin Storage access");

  const writes = [];
  const legitimateDb = mockDb({
    renderStatus: "rendered",
    pageCount: 32,
    pageWidth: 612,
    pageHeight: 792,
    coverStoragePath: expected.cover,
    pdfStoragePath: expected.interior,
    coverURL: "https://attacker.invalid/cover.pdf",
    pdfURL: "https://attacker.invalid/book.pdf"
  }, writes);
  const legitimateBucket = mockPdfBucket({
    [expected.cover]: { token: "cover-token" },
    [expected.interior]: { token: "interior-token" }
  });
  const ensured = await ensureBookVersionArtifactUrls(
    legitimateDb,
    legitimateBucket,
    "owner-1",
    "book-1"
  );
  assert.match(ensured.coverURL, /cover\.pdf\?alt=media&token=cover-token$/);
  assert.match(ensured.pdfURL, /book\.pdf\?alt=media&token=interior-token$/);
  assert.strictEqual(writes.length, 1);
  assert.notStrictEqual(writes[0].data.coverURL, "https://attacker.invalid/cover.pdf");
  assert.notStrictEqual(writes[0].data.pdfURL, "https://attacker.invalid/book.pdf");
  assert.strictEqual(ensured.coverArtifactGeneration, "7");
  assert.strictEqual(ensured.pdfArtifactGeneration, "7");

  const invalidPdfDb = mockDb({
    coverStoragePath: expected.cover,
    pdfStoragePath: expected.interior
  });
  const invalidPdfBucket = mockPdfBucket({
    [expected.cover]: { token: "cover-token", contentType: "audio/mp4" },
    [expected.interior]: { token: "interior-token" }
  });
  await assert.rejects(
    ensureBookVersionArtifactUrls(invalidPdfDb, invalidPdfBucket, "owner-1", "book-1"),
    /not a PDF/
  );

  const validatedIds = [];
  const fingerprintRecord = {
    renderStatus: "rendered",
    pageCount: 32,
    pageWidth: 612,
    pageHeight: 792,
    coverStoragePath: expected.cover,
    pdfStoragePath: expected.interior,
    coverURL: "cover",
    pdfURL: "interior",
    coverArtifactGeneration: "7",
    coverArtifactSize: 1024,
    pdfArtifactGeneration: "8",
    pdfArtifactSize: 2048
  };
  const fingerprint = checkoutFulfillmentFingerprint(fingerprintRecord, "pod-1");
  const secondProductFingerprint = checkoutFulfillmentFingerprint(fingerprintRecord, "pod-2");
  await validateCheckoutBookArtifacts({
    userId: "owner-1",
    expectedItems: [
      { bookVersionId: "book-1", selectedPodPackageId: "pod-1", fulfillmentFingerprint: fingerprint },
      {
        bookVersionId: "book-1",
        selectedPodPackageId: "pod-2",
        fulfillmentFingerprint: secondProductFingerprint
      }
    ],
    ensureArtifacts: async (userId, bookVersionId) => {
      assert.strictEqual(userId, "owner-1");
      validatedIds.push(bookVersionId);
      return fingerprintRecord;
    }
  });
  assert.deepStrictEqual(validatedIds, ["book-1"]);
  await assert.rejects(
    validateCheckoutBookArtifacts({
      userId: "owner-1",
      expectedItems: [{
        bookVersionId: "book-1",
        selectedPodPackageId: "pod-1",
        fulfillmentFingerprint: fingerprint
      }],
      ensureArtifacts: async () => ({ ...fingerprintRecord, pdfArtifactGeneration: "changed" })
    }),
    /changed after pricing/
  );

  console.log("storageArtifactUrls.test.js: all assertions passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
