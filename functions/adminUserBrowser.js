const admin = require("firebase-admin");
const { HttpsError } = require("firebase-functions/v2/https");

function validDocumentId(value) {
  return typeof value === "string" && value.length > 0 && Buffer.byteLength(value, "utf8") <= 1500 && !value.includes("/") && value !== "." && value !== "..";
}

function requireUserId(value) {
  if (!validDocumentId(value) || value.length > 128) throw new HttpsError("invalid-argument", "A valid userId is required.");
  return value;
}

function isoTimestamp(value) {
  return value && typeof value.toDate === "function" ? value.toDate().toISOString() : null;
}

function accountCreationTimestamp(authUser, fallback) {
  const milliseconds = Date.parse(authUser?.metadata?.creationTime || "");
  return Number.isFinite(milliseconds) ? admin.firestore.Timestamp.fromMillis(milliseconds) : fallback;
}

function pageOptions(data, scope, field, supportsSort = false) {
  const sort = data.sort || "newest";
  if (!["newest", "oldest"].includes(sort) || (!supportsSort && sort !== "newest")) {
    throw new HttpsError("invalid-argument", "Unsupported sort order.");
  }
  const limit = data.limit === undefined ? 25 : data.limit;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new HttpsError("invalid-argument", "limit must be between 1 and 100.");
  const options = { scope, field, sort, limit, direction: sort === "oldest" ? "asc" : "desc", cursor: null };
  if (data.cursor != null) {
    const cursor = data.cursor;
    if (typeof cursor !== "object" || cursor.scope !== scope || cursor.sort !== sort || cursor.field !== field ||
        !validDocumentId(cursor.id) || !Number.isSafeInteger(cursor.seconds) ||
        cursor.seconds < -62135596800 || cursor.seconds > 253402300799 ||
        !Number.isInteger(cursor.nanoseconds) || cursor.nanoseconds < 0 || cursor.nanoseconds > 999999999) {
      throw new HttpsError("invalid-argument", "Invalid pagination cursor. Refresh the list.");
    }
    options.cursor = cursor;
  }
  return options;
}

async function queryPage(collection, options) {
  let query = collection.orderBy(options.field, options.direction)
    .orderBy(admin.firestore.FieldPath.documentId(), options.direction);
  if (options.cursor) {
    query = query.startAfter(new admin.firestore.Timestamp(options.cursor.seconds, options.cursor.nanoseconds), options.cursor.id);
  }
  const snapshot = await query.limit(options.limit + 1).get();
  const docs = snapshot.docs.slice(0, options.limit);
  let nextCursor = null;
  if (snapshot.docs.length > options.limit && docs.length) {
    const last = docs[docs.length - 1];
    const timestamp = last.data()[options.field];
    nextCursor = { scope: options.scope, field: options.field, sort: options.sort, id: last.id, seconds: timestamp.seconds, nanoseconds: timestamp.nanoseconds };
  }
  return { docs, nextCursor };
}

function userRecord(doc, authUser) {
  const data = doc.data();
  return {
    userId: doc.id,
    displayName: authUser?.displayName || data.displayName || data.profileName || "",
    email: authUser ? (authUser.email || "") : (data.email || ""),
    isAnonymous: authUser ? authUser.providerData.length === 0 : data.isAnonymous === true,
    createdAt: isoTimestamp(data.accountCreatedAt),
    lastActiveAt: isoTimestamp(data.lastActiveAt)
  };
}

function memoryRecord(doc) {
  const data = doc.data();
  const text = [data.transcriptionEdited, data.transcription, data.transcriptionRaw, data.text]
    .find(value => typeof value === "string" && value.trim().length > 0) || "";
  return { memoryId: doc.id, prompt: data.prompt || "", text: text.slice(0, 30000), textTruncated: text.length > 30000, createdAt: isoTimestamp(data.createdAt), profileName: data.profileName || "", chapter: data.chapter || "" };
}

function createUserBrowserHandlers({ db, auth, assertAdmin }) {
  return {
    listUsers: async request => {
      assertAdmin(request);
      const options = pageOptions(request.data || {}, "users", "accountCreatedAt", true);
      const page = await queryPage(db.collection("users"), options);
      const result = page.docs.length ? await auth.getUsers(page.docs.map(doc => ({ uid: doc.id }))) : { users: [] };
      const authById = new Map(result.users.map(user => [user.uid, user]));
      return { users: page.docs.map(doc => userRecord(doc, authById.get(doc.id))), nextCursor: page.nextCursor };
    },
    listMemories: async request => {
      assertAdmin(request);
      const userId = requireUserId(request.data?.userId);
      const scope = `users/${userId}/memories`;
      const page = await queryPage(db.collection(scope), pageOptions(request.data || {}, scope, "createdAt"));
      return { memories: page.docs.map(memoryRecord), nextCursor: page.nextCursor };
    }
  };
}

async function updateMissingTimestamp(db, ref, field, timestamp) {
  return db.runTransaction(async transaction => {
    const fresh = await transaction.get(ref);
    if (!fresh.exists || fresh.data()[field] != null) return false;
    transaction.update(ref, { [field]: timestamp });
    return true;
  });
}

module.exports = { validDocumentId, requireUserId, isoTimestamp, accountCreationTimestamp, pageOptions, queryPage, userRecord, memoryRecord, createUserBrowserHandlers, updateMissingTimestamp };
