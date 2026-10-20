const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const fs = require("node:fs");
const browser = require("./adminUserBrowser");
const { backfillCollection } = require("./scripts/backfill-admin-browser-dates");
const timestamp = new admin.firestore.Timestamp(1700000000, 123456789);
const doc = (id, data = {}) => ({ id, data: () => data, createTime: timestamp, ref: { id } });
function fakeCollection(docs) {
  const calls = [];
  const query = { orderBy(...args) { calls.push(["orderBy", ...args]); return this; }, startAfter(...args) { calls.push(["startAfter", ...args]); return this; }, limit(value) { calls.push(["limit", value]); return this; }, async get() { calls.push(["get"]); return { docs }; } };
  return { query, calls };
}
test("IDs and pagination input reject malformed or cross-scope cursors", () => {
  for (const value of [null, "", "a/b", ".", "..", "x".repeat(129)]) assert.throws(() => browser.requireUserId(value));
  assert.equal(browser.requireUserId("abc"), "abc");
  assert.equal(browser.validDocumentId("valid"), true);
  assert.throws(() => browser.pageOptions({ limit: "25" }, "users", "accountCreatedAt", true));
  assert.throws(() => browser.pageOptions({ sort: "activity" }, "users", "accountCreatedAt", true));
  assert.throws(() => browser.pageOptions({ sort: "oldest" }, "memories", "createdAt"));
  const valid = { scope: "users", field: "accountCreatedAt", sort: "newest", id: "abc", seconds: timestamp.seconds, nanoseconds: timestamp.nanoseconds };
  assert.deepEqual(browser.pageOptions({ cursor: valid }, "users", "accountCreatedAt", true).cursor, valid);
  for (const change of [{ scope: "users/other/books" }, { sort: "oldest" }, { nanoseconds: -1 }, { nanoseconds: 1e9 }, { seconds: Infinity }, { field: "createdAt" }, { id: "x/y" }]) {
    assert.throws(() => browser.pageOptions({ cursor: { ...valid, ...change } }, "users", "accountCreatedAt", true));
  }
});
test("timestamp normalization preserves canonical Auth creation and safe fallback", () => {
  assert.equal(browser.isoTimestamp(null), null);
  assert.equal(browser.isoTimestamp(timestamp), timestamp.toDate().toISOString());
  assert.equal(browser.accountCreationTimestamp(null, timestamp), timestamp);
  assert.equal(browser.accountCreationTimestamp({ metadata: { creationTime: "2020-01-01T00:00:00Z" } }, timestamp).toDate().getUTCFullYear(), 2020);
});
test("query orders before limit, returns precise cursor, and supports oldest", async () => {
  const fake = fakeCollection([doc("b", { accountCreatedAt: timestamp }), doc("a", { accountCreatedAt: timestamp })]);
  const options = browser.pageOptions({ limit: 1 }, "users", "accountCreatedAt", true);
  const page = await browser.queryPage(fake.query, options);
  assert.deepEqual(fake.calls.map(call => call[0]), ["orderBy", "orderBy", "limit", "get"]);
  assert.deepEqual(fake.calls[0], ["orderBy", "accountCreatedAt", "desc"]);
  assert.equal(page.docs.length, 1);
  assert.equal(page.nextCursor.nanoseconds, 123456789);
  const next = fakeCollection([]);
  const result = await browser.queryPage(next.query, browser.pageOptions({ cursor: page.nextCursor }, "users", "accountCreatedAt", true));
  assert.equal(next.calls[2][0], "startAfter");
  assert.equal(next.calls[2][1].nanoseconds, timestamp.nanoseconds);
  assert.equal(result.nextCursor, null);
  const oldest = fakeCollection([]);
  await browser.queryPage(oldest.query, browser.pageOptions({ sort: "oldest" }, "users", "accountCreatedAt", true));
  assert.equal(oldest.calls[0][2], "asc");
});
test("record shapes use edited memories and current Auth identity", () => {
  const memory = browser.memoryRecord(doc("m", { transcriptionEdited: "edited", transcription: "raw", createdAt: timestamp }));
  assert.equal(memory.text, "edited");
  assert.equal(browser.memoryRecord(doc("m", { transcriptionEdited: " ", transcription: "canonical" })).text, "canonical");
  assert.equal(browser.memoryRecord(doc("m")).text, "");
  const long = browser.memoryRecord(doc("m", { transcription: "a".repeat(40000) }));
  assert.equal(long.text.length, 30000);
  assert.equal(long.textTruncated, true);
  const user = browser.userRecord(doc("u", { email: "stale", accountCreatedAt: timestamp }), { email: "current", displayName: "Name", providerData: [{}] });
  assert.equal(user.email, "current");
  assert.equal(user.isAnonymous, false);
  assert.equal(browser.userRecord(doc("u", { profileName: "Profile", isAnonymous: true })).displayName, "Profile");
});
test("handlers authorize before reads and enrich only returned page", async () => {
  const denied = browser.createUserBrowserHandlers({ assertAdmin: () => { throw Error("denied"); } });
  await assert.rejects(denied.listUsers({}), /denied/);
  await assert.rejects(denied.listMemories({}), /denied/);
  const fake = fakeCollection([doc("u", { accountCreatedAt: timestamp }), doc("extra", { accountCreatedAt: timestamp })]);
  let lookup;
  const handlers = browser.createUserBrowserHandlers({ db: { collection: () => fake.query }, auth: { async getUsers(ids) { lookup = ids; return { users: [{ uid: "u", email: "fresh", providerData: [] }] }; } }, assertAdmin: () => {} });
  const users = await handlers.listUsers({ data: { limit: 1 } });
  assert.deepEqual(lookup, [{ uid: "u" }]);
  assert.equal(users.users[0].email, "fresh");
  const memories = await handlers.listMemories({ data: { userId: "u" } });
  assert.equal(memories.memories.length, 2);
  await assert.rejects(handlers.listMemories({ data: { userId: "x/y" } }));
});
test("update never recreates deleted documents or overwrites established timestamps", async () => {
  for (const [exists, data, expected] of [[false, {}, false], [true, { createdAt: timestamp }, false], [true, {}, true]]) {
    const writes = [];
    const db = { runTransaction: callback => callback({ get: async () => ({ exists, data: () => data }), update: (...args) => writes.push(args) }) };
    assert.equal(await browser.updateMissingTimestamp(db, {}, "createdAt", timestamp), expected);
    assert.equal(writes.length, expected ? 1 : 0);
  }
});
test("migration defaults can scan without writes and applies only missing dates", async () => {
  const fake = fakeCollection([doc("m", {}), doc("n", { createdAt: timestamp })]);
  const stats = { scanned: 0, missing: 0, updated: 0 };
  await backfillCollection(null, fake.query, "createdAt", d => d.createTime, false, stats);
  assert.deepEqual(stats, { scanned: 2, missing: 1, updated: 0 });
  const db = { runTransaction: callback => callback({ get: async () => ({ exists: true, data: () => ({}) }), update: () => {} }) };
  const applied = { scanned: 0, missing: 0, updated: 0 };
  await backfillCollection(db, fake.query, "createdAt", d => d.createTime, true, applied);
  assert.equal(applied.updated, 1);
});
test("existing books callable retains admin guard and server-side ordered pagination", () => {
  const source = fs.readFileSync(require.resolve("./index"), "utf8");
  const code = source.slice(source.indexOf("exports.adminListUserBooks ="), source.indexOf("exports.adminVerifyOrderPdfs ="));
  assert.ok(code.indexOf("assertMemoirAdmin(request)") < code.indexOf("adminBrowser.queryPage"));
  assert.match(code, /pageOptions\(request.data \|\| \{\}, scope, "createdAt"\)/);
  assert.match(code, /nextCursor: page.nextCursor/);
  assert.match(source, /accountCreationTimestamp\(authUser, snap.createTime\)/);
});

test("book naming retries preserve identity and never resurrect missing books or users", async () => {
  const naming = require("./naming");
  function database(initial) {
    const records = new Map(Object.entries(initial));
    const writes = [];
    const db = {
      collection: path => ({ doc: id => ({ path: `${path}/${id}` }) }),
      runTransaction: callback => callback({
        get: async ref => ({ exists: records.has(ref.path), data: () => records.get(ref.path) }),
        update: (ref, data) => { assert.ok(records.has(ref.path)); writes.push(ref.path); records.set(ref.path, { ...records.get(ref.path), ...data }); },
        set: (ref, data) => { writes.push(ref.path); records.set(ref.path, { ...records.get(ref.path), ...data }); }
      })
    };
    return { db, records, writes };
  }
  const ref = { path: "users/u/bookVersions/b" };
  const complete = database({ "users/u": { userHandle: "caleb1" }, [ref.path]: {}, "counters/globalBooks": { next: 8 } });
  assert.equal(await naming.ensureBookDisplayNameAllocated(complete.db, ref, "u"), "caleb1_book9");
  assert.equal(await naming.ensureBookDisplayNameAllocated(complete.db, ref, "u"), "caleb1_book9");
  assert.equal(complete.records.get("counters/globalBooks").next, 9);
  assert.equal(complete.writes.filter(path => path === ref.path).length, 1);
  const deletedBook = database({ "users/u": { userHandle: "caleb1" } });
  assert.equal(await naming.ensureBookDisplayNameAllocated(deletedBook.db, ref, "u"), null);
  assert.equal(deletedBook.writes.length, 0);
  const deletedUser = database({ [ref.path]: {} });
  assert.equal(await naming.ensureBookDisplayNameAllocated(deletedUser.db, ref, "u"), null);
  assert.equal(deletedUser.writes.length, 0);
  assert.equal(await naming.ensureUserHandleAllocated(deletedUser.db, "u", { requireExisting: true }), null);
  assert.equal(deletedUser.writes.length, 0);
  const unnamed = database({ "users/u": { displayName: "Caleb" }, [ref.path]: {} });
  assert.equal(await naming.ensureBookDisplayNameAllocated(unnamed.db, ref, "u"), "caleb1_book1");
});
