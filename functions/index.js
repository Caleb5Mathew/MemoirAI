const admin = require("firebase-admin");
const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const { PDFDocument } = require("pdf-lib");
const crypto = require("crypto");
const Stripe = require("stripe");
const { computeBookBaseCentsFromLuluLineMake, sumCartLineShippingCents } = require("./merchantPricingMath");
const {
  mustAbortPdfPackagingForMissingCoverUrl,
  nextCoverPreconditionAttemptMeta,
  COVER_PRECONDITION_EXHAUSTED_STATUS
} = require("./bookVersionPdfGuards");
const { ensureBookVersionArtifactUrls } = require("./storageArtifactUrls");
const naming = require("./naming");
const { createOrderMirrorHandler } = require("./purchasedBooks");
const { opsAlertSmtpUrl, sendOpsAlert } = require("./opsAlerts");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const bucket = admin.storage().bucket();

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const luluClientKey = defineSecret("LULU_CLIENT_KEY");
const luluClientSecret = defineSecret("LULU_CLIENT_SECRET");
const luluWebhookSecretParam = defineSecret("LULU_WEBHOOK_SECRET");
/** Server-side only; enable Places Autocomplete + Geocoding for checkout address typeahead */
const googlePlacesApiKey = defineSecret("GOOGLE_PLACES_API_KEY");

const LULU_SANDBOX = process.env.LULU_USE_SANDBOX === "true";
const LULU_ENDPOINTS = {
  production: {
    baseUrl: "https://api.lulu.com",
    authUrl: "https://api.lulu.com/auth/realms/glasstree/protocol/openid-connect/token"
  },
  sandbox: {
    baseUrl: "https://api.sandbox.lulu.com",
    authUrl: "https://api.sandbox.lulu.com/auth/realms/glasstree/protocol/openid-connect/token"
  }
};

const LULU_SHIPPING_LEVELS = [
  { level: "MAIL", label: "Standard Mail" },
  { level: "PRIORITY_MAIL", label: "Priority Mail" },
  { level: "GROUND_HD", label: "Ground (Home)" },
  { level: "GROUND_BUS", label: "Ground (Business)" },
  { level: "GROUND", label: "Ground" },
  { level: "EXPEDITED", label: "Expedited" },
  { level: "EXPRESS", label: "Express" }
];

function jsonError(res, code, message) {
  res.status(code).json({ status: "failed", message });
}

/** Restricts HTTPS callables to ops/support (set `ADMIN_EMAILS` env comma-separated, or Auth custom claim `admin: true`). */
function assertMemoirAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }
  const emails = String(process.env.ADMIN_EMAILS || "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  const email = String(request.auth.token.email || "").toLowerCase();
  if (emails.length && email && emails.includes(email)) {
    return;
  }
  if (request.auth.token.admin === true) {
    return;
  }
  throw new HttpsError("permission-denied", "Admin only");
}

/** When false (default), paid orders wait for manual Print via ops UI / fulfillOrder. Set AUTO_FULFILL_PAID_ORDERS=true to restore immediate Lulu submit. */
function isAutoFulfillPaidOrdersEnabled() {
  return String(process.env.AUTO_FULFILL_PAID_ORDERS || "").trim().toLowerCase() === "true";
}

/** When false (default), callables accept requests without an App Check token. Set ENFORCE_APP_CHECK=true once the iOS App Check SDK has shipped. */
function isAppCheckEnforced() {
  return String(process.env.ENFORCE_APP_CHECK || "").trim().toLowerCase() === "true";
}

function firestoreTimestampToIso(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  if (value._seconds != null) {
    return new Date(value._seconds * 1000).toISOString();
  }
  return null;
}

/** Shape an order doc for the ops print queue (adminListPrintOrders). */
function orderRecordForOpsQueue(orderId, userId, data) {
  const d = data && typeof data === "object" ? data : {};
  const pricing = d.pricing && typeof d.pricing === "object" ? d.pricing : {};
  const ship = d.shippingAddress && typeof d.shippingAddress === "object" ? d.shippingAddress : {};
  const totalCents = pricing.totalCents != null ? pricing.totalCents : d.lineTotalCents;
  return {
    orderId: d.orderId || orderId,
    userId,
    status: d.status || null,
    isTestOrder: Boolean(d.isTestOrder),
    refundStatus: d.refundStatus || null,
    disputeStatus: d.disputeStatus || null,
    fulfillmentHold: Boolean(d.fulfillmentHold),
    needsPrintAction: !d.fulfillmentHold && !d.luluPrintJobId &&
      (d.status === "paid" || d.status === "lulu_failed" ||
        (d.status === "pending_fulfillment" && !d.luluPrintJobId)),
    customerEmail: d.customerEmail || null,
    printTitle: d.printTitle || null,
    bookDisplayName: d.bookDisplayName || null,
    productTitle: d.productTitle || null,
    bookVersionId: d.bookVersionId || null,
    quantity: d.quantity != null ? d.quantity : 1,
    shippingLevel: d.shippingLevel || null,
    shippingAddress: ship,
    coverURL: d.coverURL || null,
    pdfURL: d.pdfURL || null,
    coverPdfStoragePath: d.coverPdfStoragePath || null,
    interiorPdfStoragePath: d.interiorPdfStoragePath || null,
    totalCents,
    currency: pricing.currency || "usd",
    stripePaymentIntentId: d.stripePaymentIntentId || null,
    stripeSessionId: d.stripeSessionId || null,
    luluPrintJobId: d.luluPrintJobId || null,
    luluError: d.luluError || null,
    luluTrackingUrl: d.luluTrackingUrl || null,
    luluTotalCostInclTax: d.luluTotalCostInclTax != null ? d.luluTotalCostInclTax : null,
    createdAt: firestoreTimestampToIso(d.createdAt),
    updatedAt: firestoreTimestampToIso(d.updatedAt)
  };
}

function getStripeApiKey() {
  const raw = String(stripeSecretKey.value() || "");
  const trimmed = raw.trim();
  if (!trimmed) {
    throw new Error("Stripe secret key is empty");
  }
  if (raw !== trimmed) {
    console.warn("STRIPE_SECRET_KEY had surrounding whitespace; trimmed before Stripe client init.");
  }
  if (/[\r\n]/.test(trimmed)) {
    throw new Error("Stripe secret key contains newline characters");
  }
  return trimmed;
}

function getStripeWebhookSecret() {
  const raw = String(stripeWebhookSecret.value() || "");
  const trimmed = raw.trim();
  if (!trimmed) {
    throw new Error("Stripe webhook secret is empty");
  }
  if (raw !== trimmed) {
    console.warn("STRIPE_WEBHOOK_SECRET had surrounding whitespace; trimmed before signature verification.");
  }
  if (/[\r\n]/.test(trimmed)) {
    throw new Error("Stripe webhook secret contains newline characters after trim");
  }
  return trimmed;
}

function createStripeClient({ maxNetworkRetries = 1, timeoutMs = 20 * 1000 } = {}) {
  return new Stripe(getStripeApiKey(), {
    maxNetworkRetries,
    timeout: timeoutMs
  });
}

function isLikelyTransientStripeError(error) {
  const type = String(error?.type || "");
  const code = String(error?.code || "");
  const msg = String(error?.message || error || "").toLowerCase();
  return type === "StripeConnectionError"
    || code === "ECONNRESET"
    || code === "ECONNREFUSED"
    || code === "EHOSTUNREACH"
    || code === "ENETUNREACH"
    || code === "EAI_AGAIN"
    || code === "ETIMEDOUT"
    || msg.includes("connection to stripe")
    || msg.includes("connection error")
    || msg.includes("socket hang up")
    || msg.includes("network")
    || msg.includes("timed out")
    || msg.includes("econnreset");
}

async function createStripeCheckoutSessionWithRetry(stripe, payload, logLabel, idempotencyKey) {
  const maxAttempts = 3;
  const resolvedKey = resolveStripeCheckoutIdempotencyKey(idempotencyKey, logLabel);
  let lastError = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      if (attempt > 1) {
        console.warn(`${logLabel} stripe checkout retry attempt=${attempt}/${maxAttempts}`);
      }
      return await stripe.checkout.sessions.create(payload, { idempotencyKey: resolvedKey });
    } catch (error) {
      lastError = error;
      const transient = isLikelyTransientStripeError(error);
      const canRetry = transient && attempt < maxAttempts;
      console.warn(
        `${logLabel} stripe checkout create failed attempt=${attempt} transient=${transient} ` +
        `type=${String(error?.type || "")} code=${String(error?.code || "")} message=${String(error?.message || error)}`
      );
      if (!canRetry) {
        throw error;
      }
      const baseBackoff = Math.min(1500, 250 * Math.pow(2, attempt - 1));
      const jitter = Math.floor(Math.random() * 250);
      const backoffMs = baseBackoff + jitter;
      await new Promise((resolve) => setTimeout(resolve, backoffMs));
    }
  }
  throw lastError || new Error("Stripe session create failed");
}

/** Fast checkout (quote + session split). Default on; set FAST_CHECKOUT_ENABLED=false to disable server-side. */
function isFastCartCheckoutEnabled() {
  return process.env.FAST_CHECKOUT_ENABLED !== "false";
}

/**
 * Stripe Checkout session create failed (non-transient). Firebase iOS often omits HttpsError `details`
 * for code `internal` (see firebase-ios-sdk#11376), so clients only see "INTERNAL". Use `failed-precondition`
 * and put Stripe text in the top-level message for Xcode / in-app diagnostics.
 */
function throwStripeCheckoutSessionHttpsError(err, detailFields) {
  const stripeMessage = String(err?.message || err || "unknown");
  const prefix =
    "Unable to start secure checkout. If this persists, check Stripe Dashboard (Developers → Logs). ";
  const tail = stripeMessage.length > 280 ? `${stripeMessage.slice(0, 280)}…` : stripeMessage;
  const message = (prefix + tail).slice(0, 480);
  throw new HttpsError("failed-precondition", message, {
    ...detailFields,
    stripeType: err?.type || null,
    stripeCode: err?.code || null,
    stripeMessage
  });
}

const CART_CHECKOUT_QUOTE_TTL_MS = 30 * 60 * 1000;

function normalizeCartItemsForHash(items) {
  const rows = (items || []).map((row) => ({
    bookVersionId: String(row.bookVersionId || ""),
    productOptionId: row.productOptionId ? String(row.productOptionId) : "",
    quantity: Math.min(99, Math.max(1, parseInt(row.quantity, 10) || 1))
  }));
  rows.sort((a, b) => {
    const c = a.bookVersionId.localeCompare(b.bookVersionId);
    if (c !== 0) return c;
    const d = a.productOptionId.localeCompare(b.productOptionId);
    if (d !== 0) return d;
    return a.quantity - b.quantity;
  });
  return rows;
}

function normalizeShippingForHash(addr) {
  if (!addr || typeof addr !== "object") return {};
  return {
    name: String(addr.name || "").trim(),
    street1: String(addr.street1 || "").trim(),
    city: String(addr.city || "").trim(),
    stateCode: String(addr.stateCode || "").trim().toUpperCase(),
    countryCode: String(addr.countryCode || "").trim().toUpperCase(),
    postcode: String(addr.postcode || "").trim().toUpperCase(),
    phone: String(addr.phone || "").trim()
  };
}

function computeCartCheckoutPayloadHash(items, shippingAddress, shippingLevel) {
  const payload = {
    items: normalizeCartItemsForHash(items),
    shippingAddress: normalizeShippingForHash(shippingAddress),
    shippingLevel: String(shippingLevel || "MAIL").toUpperCase()
  };
  const json = JSON.stringify(payload);
  return crypto.createHash("sha256").update(json).digest("hex");
}

function sanitizeIdempotencyKey(raw) {
  const s = String(raw || "").trim().slice(0, 256);
  if (!s || s.length < 8) {
    return null;
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(s)) {
    return null;
  }
  return s;
}

/** Stripe requires Idempotency-Key length 8–255 and URL-safe characters; never omit or send an invalid key. */
function resolveStripeCheckoutIdempotencyKey(preferred, logLabel) {
  const fromPreferred = sanitizeIdempotencyKey(preferred);
  if (fromPreferred) {
    return fromPreferred;
  }
  const label = String(logLabel || "checkout").replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64) || "checkout";
  const suffix = crypto.randomBytes(16).toString("hex");
  const candidate = `${label}_${Date.now()}_${suffix}`.slice(0, 256);
  const fromGenerated = sanitizeIdempotencyKey(candidate);
  if (fromGenerated) {
    return fromGenerated;
  }
  return `idem_${crypto.randomBytes(24).toString("hex")}`;
}

/** Resume token for fast checkout: same id as `pendingCartCheckouts` / `checkoutAttempts` doc (`book1`, `book2`, …). */
function sanitizeCheckoutInstanceId(raw) {
  const s = String(raw || "").trim();
  if (!/^book\d+$/.test(s)) {
    return null;
  }
  if (s.length > 96) {
    return null;
  }
  return s;
}

/** Optional client correlation (UUID, etc.) stored on `checkoutAttempts` for logs; not used as Firestore doc id. */
function sanitizeClientCorrelationId(raw) {
  const s = String(raw || "").trim().slice(0, 256);
  if (!s || s.length < 8) {
    return null;
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(s)) {
    return null;
  }
  return s;
}

const userCheckoutSeqRef = (userId) =>
  db.collection("users").doc(userId).collection("_checkoutSeq").doc("v");

/**
 * Next monotonic `book{N}` id for this user (legacy cart path — attempt doc not used).
 */
async function allocateNextBookCheckoutId(userId) {
  const seqRef = userCheckoutSeqRef(userId);
  return db.runTransaction(async (tx) => {
    const cSnap = await tx.get(seqRef);
    const prev = cSnap.exists && cSnap.data() ? Number(cSnap.data().next) || 0 : 0;
    const next = prev + 1;
    tx.set(
      seqRef,
      { next, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    return `book${next}`;
  });
}

/** User-facing memoir title from a `bookVersions` Firestore document (matches client `BookVersionRecord` fallbacks). */
function printTitleFromBookVersionRecord(record) {
  const rec = record && typeof record === "object" ? record : {};
  const pt = rec.printTitle != null ? String(rec.printTitle).trim() : "";
  if (pt) {
    return pt;
  }
  const pages = Array.isArray(rec.pages) ? rec.pages : [];
  const first = pages[0];
  const t = first && first.title != null ? String(first.title).trim() : "";
  return t || null;
}

/**
 * Shared Lulu pricing + Stripe line items for cart checkout (used by legacy create + quote + fast session).
 */
async function buildCartCheckoutResolved(userId, items, shippingAddress, shippingLevel, logPrefix) {
  const stripeLineItems = [];
  const resolvedItems = [];
  const cartLineItemsForWholeOrderShip = [];
  const allWarnings = [];
  let suggestedAddress = null;
  let booksSubtotalCents = 0;
  const lineShippingCentsList = [];
  let firstResolvedLine = null;
  let firstLineQuantity = 1;

  for (let i = 0; i < items.length; i += 1) {
    const row = items[i] || {};
    const bookVersionId = row.bookVersionId;
    const productOptionId = row.productOptionId || null;
    const quantity = Math.min(99, Math.max(1, parseInt(row.quantity, 10) || 1));
    if (!bookVersionId) {
      throw new HttpsError("invalid-argument", `items[${i}].bookVersionId is required`);
    }

    let resolved;
    try {
      resolved = await pricingForCartLine(
        userId,
        bookVersionId,
        productOptionId,
        shippingAddress,
        shippingLevel,
        `${logPrefix}:${i}:${bookVersionId}`,
        quantity
      );
    } catch (err) {
      if (err instanceof HttpsError) {
        const prev = err.details && typeof err.details === "object" ? err.details : {};
        throw new HttpsError(err.code, err.message, {
          ...prev,
          stage: "line_pricing",
          lineIndex: i,
          bookVersionId
        });
      }
      throw new HttpsError("failed-precondition", String(err?.message || err || "Line pricing failed"), {
        stage: "line_pricing",
        lineIndex: i,
        bookVersionId
      });
    }
    for (const w of resolved.warnings) {
      allWarnings.push(w);
    }
    if (!suggestedAddress && resolved.suggestedAddress) {
      suggestedAddress = resolved.suggestedAddress;
    }
    if (!firstResolvedLine) {
      firstResolvedLine = resolved;
      firstLineQuantity = quantity;
    }

    const lineBook = resolved.pricing.bookBaseCents;
    const lineShip = resolved.pricing.shippingCents;
    lineShippingCentsList.push(lineShip);
    booksSubtotalCents += lineBook;
    const unitBook = quantity > 0 ? Math.round(lineBook / quantity) : lineBook;
    const unitCents = quantity > 0 ? Math.round(lineBook / quantity) : lineBook;

    cartLineItemsForWholeOrderShip.push({
      podPackageId: resolved.inputs.podPackageId,
      pageCount: resolved.inputs.pageCount,
      quantity
    });

    const versionRecord = resolved.inputs.record || {};
    const profileId = versionRecord.profileId != null ? String(versionRecord.profileId) : null;
    const printTitle = printTitleFromBookVersionRecord(versionRecord);

    resolvedItems.push({
      bookVersionId,
      profileId,
      printTitle,
      productOptionId: resolved.inputs.selectedOption.optionId,
      selectedPodPackageId: resolved.inputs.selectedOption.podPackageId,
      quantity,
      unitCents,
      lineTotalCents: lineBook,
      lineBookBaseCents: lineBook,
      lineShippingCents: 0,
      unitBookBaseCents: unitBook,
      unitShippingCents: 0,
      coverStoragePath: resolved.coverStoragePath,
      pdfStoragePath: resolved.pdfStoragePath,
      coverURL: resolved.coverURL || null,
      pdfURL: resolved.pdfURL || null,
      bookDisplayName: versionRecord.bookDisplayName || null,
      userHandle: versionRecord.userHandle || null,
      pageCount: resolved.inputs.pageCount,
      productTitle: resolved.inputs.selectedOption.title,
      dimensionsLabel: resolved.dimensionsLabel
    });

    stripeLineItems.push({
      price_data: {
        currency: "usd",
        product_data: {
          name: `MemoirAI — ${resolved.inputs.selectedOption.title}`,
          description: `${resolved.dimensionsLabel} · ${resolved.inputs.pageCount} pages · qty ${quantity}`
        },
        unit_amount: lineBook
      },
      quantity: 1
    });
  }

  // Each cart line is fulfilled as its own separate Lulu print job (= its own shipped package),
  // so the merchant-facing shipping charge is the SUM of every line's own Lulu shipping quote
  // (already computed per line above, via the same calculateLuluCostWithRetry call used for
  // book pricing) — not one combined "ships together" quote, which would undercharge whenever
  // the cart has more than one line.
  const summedLineShippingCents = sumCartLineShippingCents(lineShippingCentsList);
  const orderShippingCents = summedLineShippingCents;

  if (orderShippingCents > 0) {
    stripeLineItems.push({
      price_data: {
        currency: "usd",
        product_data: {
          name: "Shipping",
          description: `${cartLineItemsForWholeOrderShip.length} package(s) · ${shippingLevel || "MAIL"}`
        },
        unit_amount: orderShippingCents
      },
      quantity: 1
    });
  }

  const totalCents = booksSubtotalCents + orderShippingCents;

  return {
    stripeLineItems,
    resolvedItems,
    cartLineItemsForShippingOptions: cartLineItemsForWholeOrderShip,
    booksSubtotalCents,
    orderShippingCents,
    summedLineShippingCents,
    totalCents,
    allWarnings,
    suggestedAddress,
    firstResolvedLine,
    firstLineQuantity
  };
}

async function estimateShippingMethodsForCartSnapshot({
  cartLineItemsForShippingOptions,
  shippingAddress,
  shippingLevel,
  firstResolvedLine,
  firstLineQuantity,
  logLabel
}) {
  let shippingMethods = [];
  if (cartLineItemsForShippingOptions.length > 0) {
    try {
      shippingMethods = await estimateLuluShippingMethodsForCart({
        lineItems: cartLineItemsForShippingOptions,
        shippingAddress,
        logLabel: `${logLabel}:shipOpts`
      });
    } catch (err) {
      console.warn(`${logLabel} shipping-options failed:`, String(err.message || err));
    }
  }
  if (shippingMethods.length === 0 && firstResolvedLine) {
    try {
      shippingMethods = await estimateLuluShippingMethodsForLine({
        selectedCost: firstResolvedLine.pricing.selectedCost,
        selectedShippingLevel: shippingLevel,
        podPackageId: firstResolvedLine.inputs.podPackageId,
        pageCount: firstResolvedLine.inputs.pageCount,
        shippingAddress,
        logLabel: `${logLabel}:fallbackFirstLine`,
        quantity: firstLineQuantity
      });
    } catch (err) {
      console.warn(`${logLabel} shippingMethods fallback failed:`, String(err.message || err));
    }
  }
  return shippingMethods;
}

/** Max 36 chars, URL-safe-ish (strip UUID hyphens). Used by Places API (New) session billing. */
function normalizePlacesSessionToken(raw) {
  if (raw === undefined || raw === null || String(raw).trim() === "") {
    return undefined;
  }
  const s = String(raw).replace(/-/g, "").slice(0, 36);
  return s.length ? s : undefined;
}

function throwFromGooglePlacesHttp(res, data) {
  const status = data && data.error && data.error.status;
  const message =
    (data && data.error && data.error.message) ||
    data?.message ||
    res.statusText ||
    `HTTP ${res.status}`;
  const code = String(status || "");
  if (code === "PERMISSION_DENIED" || res.status === 403) {
    throw new HttpsError(
      "failed-precondition",
      "Google Places is blocked for this project or key. Enable Places API (New) and allow this key to use it."
    );
  }
  if (code === "INVALID_ARGUMENT") {
    throw new HttpsError("invalid-argument", String(message));
  }
  if (res.status === 429 || code === "RESOURCE_EXHAUSTED") {
    throw new HttpsError("resource-exhausted", "Places quota exceeded; try again shortly.");
  }
  throw new HttpsError("failed-precondition", String(message));
}

/**
 * Places API (New) — POST places:autocomplete
 * https://places.googleapis.com/v1/places:autocomplete
 */
async function googlePlacesAutocompleteNew({ query, countryCode, sessionToken, apiKey }) {
  const body = { input: query, languageCode: "en" };
  const cc = String(countryCode || "").trim().toUpperCase();
  if (cc.length === 2) {
    body.includedRegionCodes = [cc];
  }
  const tok = normalizePlacesSessionToken(sessionToken);
  if (tok) {
    body.sessionToken = tok;
  }

  const res = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "suggestions.placePrediction.placeId,suggestions.placePrediction.text"
    },
    body: JSON.stringify(body)
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throwFromGooglePlacesHttp(res, data);
  }

  const suggestions = data.suggestions || [];
  const predictions = [];
  for (const sgg of suggestions) {
    const pp = sgg.placePrediction;
    if (!pp) {
      continue;
    }
    const placeId = pp.placeId || "";
    const description = (pp.text && pp.text.text) || "";
    if (!placeId) {
      continue;
    }
    predictions.push({ placeId, description });
  }
  return { predictions, status: predictions.length ? "OK" : "ZERO_RESULTS" };
}

function parsePlaceAddressComponentsNew(components) {
  let streetNumber = "";
  let route = "";
  let city = "";
  let stateCode = "";
  let postcode = "";
  let countryCode = "";
  for (const c of components) {
    const types = c.types || [];
    const longName = c.longText != null ? c.longText : c.long_name;
    const longText = longName != null ? String(longName) : "";
    const shortName = c.shortText != null ? c.shortText : c.short_name;
    const shortText = shortName != null ? String(shortName) : "";
    if (types.includes("street_number")) {
      streetNumber = longText;
    }
    if (types.includes("route")) {
      route = longText;
    }
    if (types.includes("locality")) {
      city = longText;
    }
    if (!city && types.includes("postal_town")) {
      city = longText;
    }
    if (!city && types.includes("sublocality")) {
      city = longText;
    }
    if (!city && types.includes("neighborhood")) {
      city = longText;
    }
    if (types.includes("administrative_area_level_1")) {
      stateCode = shortText;
    }
    if (types.includes("postal_code")) {
      postcode = longText;
    }
    if (types.includes("country")) {
      countryCode = shortText;
    }
  }
  const street1 = [streetNumber, route].filter(Boolean).join(" ").trim();
  return { street1, city, stateCode, postcode, countryCode };
}

/**
 * Places API (New) — GET places/{place_id}
 * https://places.googleapis.com/v1/places/{placeId}
 */
async function googlePlacesGetPlaceNew({ placeId, sessionToken, apiKey }) {
  let pid = String(placeId || "").trim();
  if (!pid) {
    throw new HttpsError("invalid-argument", "placeId is required");
  }
  if (pid.startsWith("places/")) {
    pid = pid.slice("places/".length);
  }

  const qs = new URLSearchParams({ languageCode: "en" });
  const tok = normalizePlacesSessionToken(sessionToken);
  if (tok) {
    qs.set("sessionToken", tok);
  }
  const url = `https://places.googleapis.com/v1/places/${encodeURIComponent(pid)}?${qs.toString()}`;

  const res = await fetch(url, {
    method: "GET",
    headers: {
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "formattedAddress,addressComponents"
    }
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throwFromGooglePlacesHttp(res, data);
  }

  const components = data.addressComponents || [];
  const parsed = parsePlaceAddressComponentsNew(components);
  return {
    formattedAddress: data.formattedAddress || data.formatted_address || "",
    shippingAddress: {
      street1: parsed.street1,
      city: parsed.city,
      stateCode: parsed.stateCode,
      postcode: parsed.postcode,
      countryCode: parsed.countryCode || "US"
    }
  };
}

async function verifyUser(req) {
  const authHeader = req.headers.authorization || "";
  if (!authHeader.startsWith("Bearer ")) {
    throw new Error("Missing bearer token");
  }
  const token = authHeader.replace("Bearer ", "").trim();
  return admin.auth().verifyIdToken(token);
}

async function requestLuluAccessToken(authUrl, encodedBasicAuth) {
  const res = await fetch(authUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Authorization": `Basic ${encodedBasicAuth}`
    },
    body: "grant_type=client_credentials"
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Lulu auth failed: ${res.status} ${text}`);
  }
  const data = await res.json();
  if (!data?.access_token) {
    throw new Error("Lulu auth failed: missing access token");
  }
  return data.access_token;
}

function isLikelyLuluInvalidClientError(error) {
  const msg = String(error?.message || "").toLowerCase();
  return msg.includes("lulu auth failed: 401") || msg.includes("invalid_client") || msg.includes("invalid client credentials");
}

function extractHttpStatusFromErrorMessage(message) {
  const m = String(message || "").match(/failed:\s*(\d{3})/i);
  return m ? Number(m[1]) : null;
}

function oppositeLuluEnvironment(environment) {
  return environment === "sandbox" ? "production" : "sandbox";
}

function isLuluCostAuthLikeError(error) {
  const msg = String(error?.message || "");
  const status = extractHttpStatusFromErrorMessage(msg);
  if (!msg.toLowerCase().includes("lulu cost calculation failed")) {
    return false;
  }
  return status === 401 || status === 403;
}

function luluFallbackDiagnostics(error) {
  const message = String(error?.message || error || "Unknown Lulu error");
  const statusCode = extractHttpStatusFromErrorMessage(message);
  let reason = "lulu_unknown_error";
  let phase = "unknown";
  if (message.toLowerCase().includes("lulu auth failed")) {
    reason = "lulu_auth_failed";
    phase = "auth";
  } else if (message.toLowerCase().includes("lulu cost calculation failed")) {
    reason = "lulu_cost_failed";
    phase = "cost_calc";
  }
  return {
    fallbackReason: reason,
    fallbackPhase: phase,
    fallbackStatusCode: statusCode,
    fallbackDetail: message.slice(0, 500)
  };
}

async function getLuluAccessToken(forcePreferredEnvironment = null) {
  const clientKey = luluClientKey.value();
  const clientSecret = luluClientSecret.value();
  if (!clientKey || !clientSecret) {
    throw new Error("LULU_CLIENT_KEY and LULU_CLIENT_SECRET must be set");
  }
  const encoded = Buffer.from(`${clientKey}:${clientSecret}`).toString("base64");

  const defaultPreferred = LULU_SANDBOX ? "sandbox" : "production";
  const preferred = LULU_ENDPOINTS[forcePreferredEnvironment] ? forcePreferredEnvironment : defaultPreferred;
  const alternate = oppositeLuluEnvironment(preferred);

  try {
    const token = await requestLuluAccessToken(LULU_ENDPOINTS[preferred].authUrl, encoded);
    return { accessToken: token, luluBaseUrl: LULU_ENDPOINTS[preferred].baseUrl, environment: preferred };
  } catch (firstErr) {
    if (!isLikelyLuluInvalidClientError(firstErr)) {
      throw firstErr;
    }
    console.warn(`Lulu auth invalid_client on ${preferred}; retrying ${alternate}.`);
    const token = await requestLuluAccessToken(LULU_ENDPOINTS[alternate].authUrl, encoded);
    return { accessToken: token, luluBaseUrl: LULU_ENDPOINTS[alternate].baseUrl, environment: alternate };
  }
}

/** POST /cover-dimensions/ — expected flat cover width/height for a POD package + page count. */
async function luluPostCoverDimensions(accessToken, luluBaseUrl, podPackageId, interiorPageCount) {
  const res = await fetch(`${luluBaseUrl}/cover-dimensions/`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      pod_package_id: String(podPackageId || "").trim(),
      interior_page_count: Math.max(1, parseInt(interiorPageCount, 10) || 1),
      unit: "inch"
    })
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Lulu cover-dimensions failed: ${res.status} ${String(text).slice(0, 400)}`);
  }
  try {
    return JSON.parse(text);
  } catch (_) {
    throw new Error(`Lulu cover-dimensions invalid JSON: ${String(text).slice(0, 200)}`);
  }
}

function clampPrintQuantity(q) {
  const n = parseInt(q, 10);
  if (!Number.isFinite(n)) {
    return 1;
  }
  return Math.min(99, Math.max(1, n));
}

/**
 * Full-cart shipping methods + delivery windows (Lulu POST /shipping-options/).
 * Accepts the same line_items shape as cost calculation (multiple pod packages / quantities).
 */
async function luluFetchShippingOptions(accessToken, luluBaseUrl, payload) {
  const res = await fetch(`${luluBaseUrl}/shipping-options/`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  if (!res.ok) {
    const text = await res.text();
    let snippet = text;
    try {
      const parsed = JSON.parse(text);
      snippet = JSON.stringify(parsed).slice(0, 400);
    } catch (_) {
      snippet = String(text).slice(0, 400);
    }
    console.warn(`luluFetchShippingOptions failed status=${res.status} snippet=${snippet}`);
    throw new Error(`Lulu shipping-options failed: ${res.status} ${snippet}`);
  }
  return res.json();
}

function isLuluShippingOptionsAuthLikeError(error) {
  const msg = String(error?.message || "");
  if (!msg.toLowerCase().includes("lulu shipping-options failed")) {
    return false;
  }
  const status = extractHttpStatusFromErrorMessage(msg);
  return status === 401 || status === 403;
}

function buildLuluShippingOptionsPayload(lineItems, shippingAddress) {
  const addr = normalizeShippingForLuluCalc(shippingAddress || {});
  return {
    currency: "USD",
    line_items: (lineItems || []).map((li) => ({
      page_count: Math.max(1, parseInt(li.pageCount, 10) || 1),
      pod_package_id: String(li.podPackageId || "").trim(),
      quantity: clampPrintQuantity(li.quantity)
    })).filter((li) => li.pod_package_id.length > 0),
    shipping_address: {
      street1: addr.street1 || "",
      city: addr.city || "",
      state_code: addr.stateCode || "",
      country: String(addr.countryCode || "US").toUpperCase().slice(0, 2),
      postcode: addr.postcode || "",
      phone_number: addr.phone || "0000000000"
    }
  };
}

function mapLuluShippingOptionsRowToMethod(row) {
  if (!row || typeof row !== "object") {
    return null;
  }
  const level = String(row.level || "").trim();
  if (!level) {
    return null;
  }
  const known = new Set(LULU_SHIPPING_LEVELS.map((it) => it.level));
  if (!known.has(level)) {
    return null;
  }
  const label = LULU_SHIPPING_LEVELS.find((it) => it.level === level)?.label || level;
  let shippingCents = 0;
  if (row.cost_excl_tax != null && row.cost_excl_tax !== "") {
    const d = parseFloat(String(row.cost_excl_tax));
    if (Number.isFinite(d)) {
      shippingCents = Math.max(0, Math.round(d * 100));
    }
  }
  let minDays = coerceIntOrNull(row.total_days_min);
  let maxDays = coerceIntOrNull(row.total_days_max);
  if (minDays == null && maxDays == null) {
    const transit = coerceIntOrNull(row.transit_time);
    if (transit != null && transit > 0) {
      minDays = transit;
      maxDays = transit;
    }
  }
  const minDate = isoDateOnly(
    row.min_delivery_date ??
    row.min_delivery ??
    row.estimated_delivery_date_min ??
    row.arrival_min
  );
  const maxDate = isoDateOnly(
    row.max_delivery_date ??
    row.max_delivery ??
    row.estimated_delivery_date_max ??
    row.arrival_max
  );
  return {
    level,
    label,
    shippingCents,
    estimatedArrivalMinDays: minDays,
    estimatedArrivalMaxDays: maxDays,
    estimatedArrivalMinDate: minDate,
    estimatedArrivalMaxDate: maxDate
  };
}

function orderShippingMethodsByKnownLevels(methods) {
  const byLevel = new Map(methods.map((m) => [m.level, m]));
  return LULU_SHIPPING_LEVELS.map((it) => byLevel.get(it.level)).filter(Boolean);
}

/**
 * Shipping speed + ETA for entire cart (all line_items in one Lulu request).
 */
async function estimateLuluShippingMethodsForCart({ lineItems, shippingAddress, logLabel }) {
  const payload = buildLuluShippingOptionsPayload(lineItems, shippingAddress);
  if (!payload.line_items.length) {
    return [];
  }
  let auth = await getLuluAccessToken();
  console.log(`${logLabel} Lulu shipping-options env=${auth.environment} lineItems=${payload.line_items.length}`);
  let raw;
  try {
    raw = await luluFetchShippingOptions(auth.accessToken, auth.luluBaseUrl, payload);
  } catch (firstErr) {
    if (!isLuluShippingOptionsAuthLikeError(firstErr)) {
      throw firstErr;
    }
    const retryEnv = oppositeLuluEnvironment(auth.environment);
    console.warn(`${logLabel} shipping-options auth-like failure; retry env=${retryEnv}`);
    auth = await getLuluAccessToken(retryEnv);
    raw = await luluFetchShippingOptions(auth.accessToken, auth.luluBaseUrl, payload);
  }
  const rows = Array.isArray(raw) ? raw : [];
  if (rows.length > 0) {
    console.log(`${logLabel} shipping-options sample=${JSON.stringify(rows[0]).slice(0, 520)}`);
  }
  const mapped = rows.map(mapLuluShippingOptionsRowToMethod).filter(Boolean);
  const ordered = orderShippingMethodsByKnownLevels(mapped);
  console.log(`${logLabel} shipping-options returned ${rows.length} rows, mapped ${ordered.length} methods`);
  return ordered;
}

async function luluCalculateCost(accessToken, luluBaseUrl, podPackageId, pageCount, shippingAddress, shippingLevel, quantity = 1) {
  const qty = clampPrintQuantity(quantity);
  const res = await fetch(`${luluBaseUrl}/print-job-cost-calculations/`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      line_items: [
        {
          pod_package_id: podPackageId,
          page_count: pageCount,
          quantity: qty
        }
      ],
      shipping_address: {
        street1: shippingAddress.street1 || "",
        city: shippingAddress.city || "",
        state_code: shippingAddress.stateCode || "",
        country_code: shippingAddress.countryCode || "US",
        postcode: shippingAddress.postcode || "",
        phone_number: shippingAddress.phone || "0000000000"
      },
      shipping_level: shippingLevel || "MAIL"
    })
  });
  if (!res.ok) {
    const text = await res.text();
    let parsed = null;
    try {
      parsed = JSON.parse(text);
    } catch (_) {
      parsed = null;
    }
    let compact = text;
    if (parsed && typeof parsed === "object") {
      const firstIssue = Array.isArray(parsed?.line_item_errors) ? parsed.line_item_errors[0] : null;
      compact = JSON.stringify({
        message: parsed.message || parsed.detail || null,
        code: parsed.code || parsed.error || null,
        firstIssue: firstIssue || null
      });
    }
    console.warn(
      `luluCalculateCost failed status=${res.status} base=${luluBaseUrl} ` +
      `snippet=${String(compact).slice(0, 300)}`
    );
    throw new Error(`Lulu cost calculation failed: ${res.status} ${compact}`);
  }
  return res.json();
}

async function calculateLuluCostWithRetry({ podPackageId, pageCount, shippingAddress, shippingLevel, logLabel, quantity = 1 }) {
  let auth = await getLuluAccessToken();
  console.log(`${logLabel} Lulu auth environment=${auth.environment}`);
  try {
    const costResult = await luluCalculateCost(
      auth.accessToken,
      auth.luluBaseUrl,
      podPackageId,
      pageCount,
      shippingAddress,
      shippingLevel,
      quantity
    );
    return { costResult, environment: auth.environment };
  } catch (costErr) {
    if (!isLuluCostAuthLikeError(costErr)) {
      throw costErr;
    }
    const retryEnv = oppositeLuluEnvironment(auth.environment);
    console.warn(`${logLabel} Lulu cost auth-like failure; retrying cost with env=${retryEnv}`);
    auth = await getLuluAccessToken(retryEnv);
    console.log(`${logLabel} Lulu retry auth environment=${auth.environment}`);
    const costResult = await luluCalculateCost(
      auth.accessToken,
      auth.luluBaseUrl,
      podPackageId,
      pageCount,
      shippingAddress,
      shippingLevel,
      quantity
    );
    return { costResult, environment: auth.environment };
  }
}

function buildLandscapeProductOptions(pricing) {
  const hardcoverPkg = pricing?.luluPodPackageId || "1100X0850FCSTDCW080CW444MXX";
  return [
    {
      optionId: "kids_hardcover_casewrap",
      title: "Hardcover (Casewrap)",
      subtitle: "Premium keepsake with matte hard cover",
      podPackageId: hardcoverPkg,
      minPages: 24,
      maxPages: 800
    },
    {
      optionId: "kids_coil_bound",
      title: "Coil Bound",
      subtitle: "Best for short books and activity-style flipping",
      podPackageId: "1100X0850FCSTDCO080CW444MXX",
      minPages: 2,
      maxPages: 470
    },
    {
      optionId: "kids_paperback_perfect",
      title: "Paperback",
      subtitle: "Softcover perfect bound",
      podPackageId: "1100X0850FCSTDPB080CW444MXX",
      minPages: 32,
      maxPages: 250
    }
  ];
}

function buildPortraitProductOptions(pricing) {
  const hardcoverPkg = pricing?.luluPodPackageId || "0850X1100FCSTDCW080CW444MXX";
  return [
    {
      optionId: "portrait_hardcover_casewrap",
      title: "Hardcover (Casewrap)",
      subtitle: "Premium keepsake with matte hard cover",
      podPackageId: hardcoverPkg,
      minPages: 24,
      maxPages: 800
    }
  ];
}

function optionsForBook(isLandscape, pricing) {
  return isLandscape ? buildLandscapeProductOptions(pricing) : buildPortraitProductOptions(pricing);
}

function optionAvailability(option, pageCount) {
  if (option.optionId === "kids_coil_bound") {
    return {
      available: false,
      reason: "Coil binding is temporarily unavailable while we finalize cover templates for Lulu."
    };
  }
  if (pageCount < option.minPages) {
    return {
      available: false,
      reason: `Requires at least ${option.minPages} pages (you have ${pageCount}).`
    };
  }
  if (pageCount > option.maxPages) {
    return {
      available: false,
      reason: `Supports up to ${option.maxPages} pages (you have ${pageCount}).`
    };
  }
  return { available: true, reason: null };
}

/**
 * Load book version + Firestore pricing config for ordering (shared by checkout + estimate).
 * `baseCents` comes from `config/pricing` → `basePriceCents` and is the **minimum retail per copy** (floor).
 * `marginPercent` is applied to Lulu's page-count-sensitive line make cost: ceil(luluMake × (1 + margin/100)).
 * @returns {Promise<{record: object, pageCount: number, podPackageId: string, baseCents: number, marginPercent: number, isLandscape: boolean, selectedOption: object, productOptions: object[]}>}
 */
async function getBookVersionOrderInputs(userId, bookVersionId, requestedOptionId = null) {
  const docRef = db.collection("users").doc(userId).collection("bookVersions").doc(bookVersionId);
  const snapshot = await docRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Book not found");
  }
  let record = snapshot.data() || {};
  try {
    const ensured = await ensureBookVersionArtifactUrls(db, bucket, userId, bookVersionId);
    if (ensured) {
      record = ensured;
    }
  } catch (e) {
    console.warn("getBookVersionOrderInputs: ensureBookVersionArtifactUrls failed", userId, bookVersionId, e);
  }
  if (record.renderStatus !== "rendered" || !record.pdfURL || !record.coverURL) {
    throw new HttpsError("failed-precondition", "Book PDF is not ready for printing yet");
  }
  const pageCount = record.pageCount || record.pages?.length || 0;
  const pdfStoragePath = record.pdfStoragePath;
  const coverStoragePath = record.coverStoragePath;
  if (!pdfStoragePath || !coverStoragePath) {
    throw new HttpsError("failed-precondition", "Book artifacts missing");
  }
  const isLandscape = (record.pageWidth || 612) > (record.pageHeight || 792);
  const pricingSnap = await db.collection("config").doc("pricing").get();
  const pricingData = pricingSnap.exists ? pricingSnap.data() : {};
  const pricing = isLandscape ? pricingData?.kidsBook : pricingData?.standardBook;
  const baseCents = pricing?.basePriceCents ?? 2999;
  const marginPercent = pricing?.marginPercent ?? 30;

  const catalog = optionsForBook(isLandscape, pricing).map((opt) => {
    const availability = optionAvailability(opt, pageCount);
    return {
      ...opt,
      available: availability.available,
      unavailableReason: availability.reason
    };
  });
  const preferred = requestedOptionId
    ? catalog.find((o) => o.optionId === requestedOptionId)
    : null;
  const selected = preferred
    || catalog.find((o) => o.available && o.optionId.includes("hardcover"))
    || catalog.find((o) => o.available)
    || null;

  if (!selected) {
    throw new HttpsError(
      "failed-precondition",
      `No print products support ${pageCount} pages for this format.`
    );
  }
  if (!selected.available) {
    throw new HttpsError(
      "failed-precondition",
      selected.unavailableReason || "Selected print product is not available for this page count."
    );
  }

  return {
    record,
    pageCount,
    podPackageId: selected.podPackageId,
    baseCents,
    marginPercent,
    isLandscape,
    selectedOption: selected,
    productOptions: catalog
  };
}

function extractLuluShippingCents(costResult) {
  const shippingInclTaxRaw = (
    (costResult?.shipping_cost && typeof costResult.shipping_cost === "object"
      ? costResult.shipping_cost.total_cost_incl_tax
      : null)
    || costResult?.shipping_cost_incl_tax
    || null
  );
  const shippingDollars = parseFloat(shippingInclTaxRaw || "0");
  return Number.isFinite(shippingDollars) ? Math.max(0, Math.round(shippingDollars * 100)) : 0;
}

function extractLuluLineItemMakeCents(costResult) {
  const firstLineItem = Array.isArray(costResult?.line_item_costs) ? costResult.line_item_costs[0] : null;
  const makeRaw = firstLineItem?.total_cost_incl_tax ?? firstLineItem?.total_cost_excl_tax ?? "0";
  const makeDollars = parseFloat(makeRaw);
  return Number.isFinite(makeDollars) ? Math.max(0, Math.round(makeDollars * 100)) : 0;
}

function normalizeShippingForLuluCalc(shippingAddress) {
  return {
    street1: shippingAddress.street1 || "",
    city: shippingAddress.city || "",
    stateCode: shippingAddress.stateCode || "",
    countryCode: shippingAddress.countryCode || "US",
    postcode: shippingAddress.postcode || "",
    phone: shippingAddress.phone || "0000000000"
  };
}

function coerceIntOrNull(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const n = parseInt(String(value), 10);
  return Number.isFinite(n) ? n : null;
}

function isoDateOnly(value) {
  const raw = String(value || "").trim();
  if (!raw) {
    return null;
  }
  const match = raw.match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : null;
}

function extractLuluArrivalEstimate(costResult) {
  const shippingCost = costResult?.shipping_cost && typeof costResult.shipping_cost === "object"
    ? costResult.shipping_cost
    : {};
  const shippingDetails = costResult?.shipping_details && typeof costResult.shipping_details === "object"
    ? costResult.shipping_details
    : {};
  const shipmentDates = costResult?.shipment_dates && typeof costResult.shipment_dates === "object"
    ? costResult.shipment_dates
    : {};

  const minDays = coerceIntOrNull(
    shippingCost.min_delivery_days ??
    shippingCost.estimated_min_days ??
    shippingCost.transit_min_days ??
    shippingCost.min_business_days ??
    shippingCost.estimated_business_days_min ??
    shippingCost.total_days_min ??
    shippingDetails.min_delivery_days ??
    shippingDetails.estimated_min_days ??
    shippingDetails.transit_min_days ??
    shippingDetails.min_business_days ??
    shippingDetails.estimated_business_days_min ??
    shippingDetails.total_days_min
  );
  const maxDays = coerceIntOrNull(
    shippingCost.max_delivery_days ??
    shippingCost.estimated_max_days ??
    shippingCost.transit_max_days ??
    shippingCost.max_business_days ??
    shippingCost.estimated_business_days_max ??
    shippingCost.total_days_max ??
    shippingDetails.max_delivery_days ??
    shippingDetails.estimated_max_days ??
    shippingDetails.transit_max_days ??
    shippingDetails.max_business_days ??
    shippingDetails.estimated_business_days_max ??
    shippingDetails.total_days_max
  );

  const minDate = isoDateOnly(
    shippingCost.arrival_min ??
    shippingCost.min_delivery_date ??
    shippingCost.estimated_delivery_date_min ??
    shippingCost.estimated_arrival_date_min ??
    shippingDetails.arrival_min ??
    shippingDetails.min_delivery_date ??
    shippingDetails.estimated_delivery_date_min ??
    shippingDetails.estimated_arrival_date_min ??
    shipmentDates.arrival_min ??
    shipmentDates.min_delivery_date ??
    shipmentDates.estimated_arrival_date_min
  );
  const maxDate = isoDateOnly(
    shippingCost.arrival_max ??
    shippingCost.max_delivery_date ??
    shippingCost.estimated_delivery_date_max ??
    shippingCost.estimated_arrival_date_max ??
    shippingDetails.arrival_max ??
    shippingDetails.max_delivery_date ??
    shippingDetails.estimated_delivery_date_max ??
    shippingDetails.estimated_arrival_date_max ??
    shipmentDates.arrival_max ??
    shipmentDates.max_delivery_date ??
    shipmentDates.estimated_arrival_date_max
  );

  return {
    estimatedArrivalMinDays: minDays,
    estimatedArrivalMaxDays: maxDays,
    estimatedArrivalMinDate: minDate,
    estimatedArrivalMaxDate: maxDate
  };
}

async function estimateLuluShippingMethodsForLine({
  selectedCost,
  selectedShippingLevel,
  podPackageId,
  pageCount,
  shippingAddress,
  logLabel,
  quantity = 1
}) {
  const qty = clampPrintQuantity(quantity);
  const methodsByLevel = new Map();
  const normalizedAddress = normalizeShippingForLuluCalc(shippingAddress || {});
  const knownLevels = new Set(LULU_SHIPPING_LEVELS.map((it) => it.level));
  const initialLevel = String(selectedShippingLevel || "MAIL");

  const registerMethod = (level, costResult) => {
    if (!knownLevels.has(level) || !costResult) {
      return;
    }
    const shippingCents = extractLuluShippingCents(costResult);
    const arrival = extractLuluArrivalEstimate(costResult);
    const label = LULU_SHIPPING_LEVELS.find((it) => it.level === level)?.label || level;
    methodsByLevel.set(level, {
      level,
      label,
      shippingCents,
      ...arrival
    });
  };

  registerMethod(initialLevel, selectedCost);

  await Promise.all(
    LULU_SHIPPING_LEVELS
      .map((it) => it.level)
      .filter((level) => level !== initialLevel)
      .map(async (level) => {
        try {
          const quote = await calculateLuluCostWithRetry({
            podPackageId,
            pageCount,
            shippingAddress: normalizedAddress,
            shippingLevel: level,
            logLabel: `${logLabel}:shippingMethod:${level}`,
            quantity: qty
          });
          registerMethod(level, quote.costResult);
        } catch (err) {
          console.warn(`${logLabel} shipping method estimate skipped level=${level}:`, String(err.message || err));
        }
      })
  );

  return LULU_SHIPPING_LEVELS
    .map((it) => methodsByLevel.get(it.level))
    .filter(Boolean);
}

async function calculateMerchantPricingBreakdown({
  inputs,
  shippingAddress,
  shippingLevel,
  logLabel,
  quantity = 1
}) {
  const qty = clampPrintQuantity(quantity);
  const selectedQuote = await calculateLuluCostWithRetry({
    podPackageId: inputs.podPackageId,
    pageCount: inputs.pageCount,
    shippingAddress,
    shippingLevel,
    logLabel,
    quantity: qty
  });
  const selectedCost = selectedQuote.costResult;
  const selectedShippingCents = extractLuluShippingCents(selectedCost);
  const selectedMakeCents = extractLuluLineItemMakeCents(selectedCost);

  const { bookBaseCents, pricingFloorApplied } = computeBookBaseCentsFromLuluLineMake({
    luluMakeLineCents: selectedMakeCents,
    marginPercent: inputs.marginPercent,
    floorCentsPerUnit: inputs.baseCents,
    quantity: qty
  });
  const shippingCents = selectedShippingCents;
  const estimatedTotalCents = bookBaseCents + shippingCents;

  return {
    selectedCost,
    bookBaseCents,
    shippingCents,
    estimatedTotalCents,
    pricingFloorApplied,
    luluShippingCostInclTax: (
      (selectedCost?.shipping_cost && typeof selectedCost.shipping_cost === "object"
        ? selectedCost.shipping_cost.total_cost_incl_tax
        : null)
      || selectedCost?.shipping_cost_incl_tax
      || null
    ),
    selectedLineItemCostInclTax: (
      Array.isArray(selectedCost?.line_item_costs) && selectedCost.line_item_costs[0]
        ? selectedCost.line_item_costs[0].total_cost_incl_tax || null
        : null
    ),
    /** @deprecated Differential paperback/coil pricing removed; always null. */
    hardcoverReferenceLineItemCostInclTax: null,
    /** @deprecated Differential hardcover reference removed; always null. */
    hardcoverReferencePageCount: null
  };
}

/**
 * Per-cart-line pricing: live Lulu + merchant formula (same as single-book checkout).
 */
async function pricingForCartLine(userId, bookVersionId, productOptionId, shippingAddress, shippingLevel, logLabel, quantity = 1) {
  const inputs = await getBookVersionOrderInputs(userId, bookVersionId, productOptionId);
  const addr = normalizeShippingForLuluCalc(shippingAddress);
  const pricing = await calculateMerchantPricingBreakdown({
    inputs,
    shippingAddress: addr,
    shippingLevel,
    logLabel,
    quantity
  });
  const { warnings, suggestedAddress } = extractLuluAddressFeedback(pricing.selectedCost);
  const record = inputs.record;
  return {
    inputs,
    pricing,
    warnings,
    suggestedAddress,
    pdfStoragePath: record.pdfStoragePath,
    coverStoragePath: record.coverStoragePath,
    pdfURL: record.pdfURL || null,
    coverURL: record.coverURL || null,
    dimensionsLabel: inputs.isLandscape ? "11x8.5\"" : "8.5x11\""
  };
}

/**
 * Lulu returns warnings on the cost-calculation response (address validation).
 */
function extractLuluAddressFeedback(costResult) {
  const raw = costResult.warnings;
  const warnings = [];
  let suggestedAddress = null;
  if (Array.isArray(raw)) {
    for (const w of raw) {
      if (w && typeof w === "object") {
        warnings.push({
          type: w.type || "",
          code: w.code || "",
          path: w.path || "",
          message: w.message || ""
        });
        const sug = w.suggested_address;
        if (!suggestedAddress && sug && typeof sug === "object") {
          suggestedAddress = {
            street1: sug.street1 || "",
            street2: sug.street2 || "",
            city: sug.city || "",
            stateCode: sug.state_code || "",
            postcode: sug.postcode || "",
            countryCode: sug.country_code || ""
          };
        }
      }
    }
  }
  /** Top-level suggested_address on some payloads */
  if (!suggestedAddress && costResult.suggested_address && typeof costResult.suggested_address === "object") {
    const sug = costResult.suggested_address;
    suggestedAddress = {
      street1: sug.street1 || "",
      street2: sug.street2 || "",
      city: sug.city || "",
      stateCode: sug.state_code || "",
      postcode: sug.postcode || "",
      countryCode: sug.country_code || ""
    };
  }
  return { warnings, suggestedAddress };
}

async function luluCreatePrintJob(accessToken, luluBaseUrl, payload) {
  const res = await fetch(`${luluBaseUrl}/print-jobs/`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Lulu create print job failed: ${res.status} ${text}`);
  }
  return res.json();
}

async function luluGetPrintJob(accessToken, luluBaseUrl, printJobId) {
  const id = String(printJobId || "").trim();
  if (!id) {
    throw new Error("Missing Lulu print job id");
  }
  const res = await fetch(`${luluBaseUrl}/print-jobs/${encodeURIComponent(id)}/`, {
    method: "GET",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    }
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Lulu get print job failed: ${res.status} ${text}`);
  }
  return res.json();
}

function mapLuluStatusToOrderStatus(status) {
  const statusMap = {
    CREATED: "submitted_to_printer",
    UNPAID: "submitted_to_printer",
    PAYMENT_IN_PROGRESS: "printing",
    PRODUCTION_READY: "printing",
    IN_PRODUCTION: "printing",
    SHIPPED: "shipped",
    DELIVERED: "delivered",
    CANCELLED: "failed",
    ERROR: "failed"
  };
  return statusMap[status] || status;
}

function resolveTrackingUrlFromLuluJob(job) {
  if (!job || typeof job !== "object") {
    return null;
  }
  if (job.tracking_url) return String(job.tracking_url);
  if (job.trackingUrl) return String(job.trackingUrl);
  if (Array.isArray(job.tracking_urls) && job.tracking_urls.length > 0) {
    return String(job.tracking_urls[0]);
  }
  if (Array.isArray(job.trackingUrls) && job.trackingUrls.length > 0) {
    return String(job.trackingUrls[0]);
  }
  return null;
}

function pushStatusHistory(existingHistory, { status, trackingUrl = null, source = "lulu_sync" }) {
  const history = Array.isArray(existingHistory) ? [...existingHistory] : [];
  history.push({
    status: status || "UNKNOWN",
    timestamp: new Date().toISOString(),
    trackingUrl: trackingUrl || null,
    source
  });
  return history;
}

async function syncOrderStatusFromLulu({ orderRef, orderData }) {
  const luluPrintJobId = orderData.luluPrintJobId;
  if (!luluPrintJobId) {
    return { synced: false, reason: "missing_lulu_print_job_id" };
  }
  const { accessToken, luluBaseUrl, environment } = await getLuluAccessToken();
  const job = await luluGetPrintJob(accessToken, luluBaseUrl, luluPrintJobId);
  const luluRawStatus = String(job.status || job.state || "UNKNOWN");
  const mapped = mapLuluStatusToOrderStatus(luluRawStatus);
  const trackingUrl = resolveTrackingUrlFromLuluJob(job);
  const statusChanged = orderData.status !== mapped;
  const trackingChanged = Boolean(trackingUrl) && trackingUrl !== orderData.luluTrackingUrl;
  const shouldAppendHistory = statusChanged || trackingChanged;

  const updates = {
    luluRawStatus,
    luluLastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };
  if (statusChanged) {
    updates.status = mapped;
  }
  if (trackingUrl) {
    updates.luluTrackingUrl = trackingUrl;
  }
  if (shouldAppendHistory) {
    updates.luluStatusHistory = pushStatusHistory(orderData.luluStatusHistory, {
      status: luluRawStatus,
      trackingUrl,
      source: "lulu_sync"
    });
  }

  await orderRef.update(updates);
  return {
    synced: true,
    environment,
    luluRawStatus,
    mappedStatus: mapped,
    statusChanged,
    trackingChanged
  };
}

async function submitPaidOrderToLulu({ orderRef, orderData, orderId, userId, source }) {
  if (orderData.isTestOrder) {
    return { submitted: false, skipped: true, reason: "test_order" };
  }
  const status = orderData.status;
  const retriable = status === "paid" || status === "lulu_failed" ||
    (status === "pending_fulfillment" && !orderData.luluPrintJobId);
  if (!retriable) {
    return { submitted: false, skipped: true, reason: `status_${status}` };
  }
  if (orderData.luluPrintJobId) {
    return { submitted: false, skipped: true, reason: "already_submitted", luluPrintJobId: orderData.luluPrintJobId };
  }

  const coverStoragePath = orderData.coverPdfStoragePath;
  const interiorStoragePath = orderData.interiorPdfStoragePath;
  if (!coverStoragePath || !interiorStoragePath) {
    throw new Error("Order missing PDF storage paths");
  }

  const [coverExists, interiorExists] = await Promise.all([
    bucket.file(coverStoragePath).exists(),
    bucket.file(interiorStoragePath).exists()
  ]);
  if (!coverExists[0]) {
    throw new Error("Cover PDF missing from Storage");
  }
  if (!interiorExists[0]) {
    throw new Error("Interior PDF missing from Storage");
  }

  const bookSnap = await db.collection("users").doc(userId)
    .collection("bookVersions").doc(orderData.bookVersionId).get();
  const bookRecord = bookSnap.exists ? bookSnap.data() : {};
  if (bookRecord.renderStatus !== "rendered") {
    throw new Error(`bookVersion renderStatus=${bookRecord.renderStatus || "missing"}, expected rendered`);
  }

  let podPackageId = orderData.selectedPodPackageId || null;
  if (!podPackageId) {
    const inputs = await getBookVersionOrderInputs(
      userId,
      orderData.bookVersionId,
      orderData.selectedProductOptionId || null
    );
    podPackageId = inputs.podPackageId;
  }

  const pageCount = bookRecord.pageCount || bookRecord.pages?.length || 0;
  let luluAuthForSubmit = null;
  if (podPackageId && pageCount > 0) {
    try {
      luluAuthForSubmit = await getLuluAccessToken();
      const dims = await luluPostCoverDimensions(
        luluAuthForSubmit.accessToken,
        luluAuthForSubmit.luluBaseUrl,
        podPackageId,
        pageCount
      );
      const expW = parseFloat(dims.width);
      const expH = parseFloat(dims.height);
      if (Number.isFinite(expW) && Number.isFinite(expH)) {
        const [coverBuf] = await bucket.file(coverStoragePath).download();
        const coverPdf = await PDFDocument.load(coverBuf);
        const page0 = coverPdf.getPage(0);
        const { width: wPt, height: hPt } = page0.getSize();
        const wIn = wPt / 72;
        const hIn = hPt / 72;
        const tol = 0.0625;
        if (Math.abs(wIn - expW) > tol || Math.abs(hIn - expH) > tol) {
          throw new Error(
            `cover_dimensions_mismatch pod=${podPackageId} pages=${pageCount} ` +
              `expected=${expW.toFixed(4)}x${expH.toFixed(4)}in actual=${wIn.toFixed(4)}x${hIn.toFixed(4)}in`
          );
        }
      }
    } catch (dimErr) {
      const msg = String(dimErr?.message || dimErr);
      if (msg.includes("cover_dimensions_mismatch")) {
        throw dimErr;
      }
      console.warn(`submitPaidOrderToLulu: cover dimension check skipped order=${orderId}: ${msg}`);
    }
  }

  await orderRef.update({
    status: "pending_fulfillment",
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  try {
    const [coverSignedUrl, interiorSignedUrl] = await Promise.all([
      getSignedUrl(coverStoragePath),
      getSignedUrl(interiorStoragePath)
    ]);

    const firstPageTitle = bookRecord.pages?.[0]?.title || "Story";
    const printTitleRaw = bookRecord.printTitle != null ? String(bookRecord.printTitle).trim() : "";
    const chosenTitle = printTitleRaw || firstPageTitle;
    const bookTitle = chosenTitle ? `${chosenTitle} (Story)` : "MemoirAI Story";

    const shippingAddress = orderData.shippingAddress || {};
    const printQty = Math.min(99, Math.max(1, parseInt(orderData.quantity, 10) || 1));
    const payload = {
      line_items: [
        {
          title: bookTitle,
          cover: { source_url: coverSignedUrl },
          interior: { source_url: interiorSignedUrl },
          pod_package_id: podPackageId,
          page_count: pageCount,
          quantity: printQty
        }
      ],
      shipping_address: {
        name: shippingAddress.name || "Customer",
        street1: shippingAddress.street1 || "",
        city: shippingAddress.city || "",
        state_code: shippingAddress.stateCode || "",
        country_code: shippingAddress.countryCode || "US",
        postcode: shippingAddress.postcode || "",
        phone_number: shippingAddress.phone || "0000000000"
      },
      contact_email: orderData.customerEmail || "",
      shipping_level: orderData.shippingLevel || "MAIL",
      external_id: orderId
    };

    const auth = luluAuthForSubmit || await getLuluAccessToken();
    console.log(`submitPaidOrderToLulu source=${source} order=${orderId} env=${auth.environment}`);
    const luluJob = await luluCreatePrintJob(auth.accessToken, auth.luluBaseUrl, payload);
    const luluJobId = luluJob.id || luluJob.external_id;
    const luluRawStatus = String(luluJob.status || luluJob.state || "CREATED");
    const mappedStatus = mapLuluStatusToOrderStatus(luluRawStatus);
    const trackingUrl = resolveTrackingUrlFromLuluJob(luluJob);

    const updates = {
      luluPrintJobId: luluJobId,
      luluRawStatus,
      status: mappedStatus,
      luluLastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      luluStatusHistory: pushStatusHistory(orderData.luluStatusHistory, {
        status: luluRawStatus,
        trackingUrl,
        source
      })
    };
    if (trackingUrl) {
      updates.luluTrackingUrl = trackingUrl;
    }
    await orderRef.update(updates);

    return {
      submitted: true,
      luluJobId,
      mappedStatus,
      luluRawStatus
    };
  } catch (err) {
    const luluError = String(err?.message || err || "Unknown Lulu submit error");
    await orderRef.update({
      status: "lulu_failed",
      luluError,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    sendOpsAlert(
      `Order fulfillment FAILED — ${orderId}`,
      `Order ${orderId} (user ${userId}, source=${source}) failed to submit to Lulu:\n${luluError}\n\n` +
        "Ops: https://memoirai-7db06.web.app/ops"
    ).catch(() => {});
    throw err;
  }
}

// GCS V4 signed URLs cannot exceed 7 days (604800s). Use 23h to avoid clock-skew rejections.
const GCS_MAX_SIGNED_URL_TTL_SEC = 82800;

async function getSignedUrl(storagePath, expiresInSeconds = GCS_MAX_SIGNED_URL_TTL_SEC) {
  const ttl = Math.min(
    Math.max(60, Math.floor(Number(expiresInSeconds) || GCS_MAX_SIGNED_URL_TTL_SEC)),
    GCS_MAX_SIGNED_URL_TTL_SEC
  );
  const file = bucket.file(storagePath);
  const [url] = await file.getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + ttl * 1000
  });
  return url;
}

/** Admin: stream a PDF (interior or cover) for an order. GET ?orderId=&userId=&type=interior|cover */
exports.adminGetOrderPdf = onRequest({ timeoutSeconds: 60, memory: "512MiB" }, async (req, res) => {
  const allowedOrigins = ["https://memoirai-7db06.web.app", "https://memoirai-7db06.firebaseapp.com"];
  const origin = req.headers.origin || "";
  res.set("Access-Control-Allow-Origin", allowedOrigins.includes(origin) ? origin : allowedOrigins[0]);
  res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  let decoded;
  try {
    decoded = await verifyUser(req);
  } catch (_) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  const isAdmin = (() => {
    const adminEmails = (process.env.ADMIN_EMAILS || "").split(",").map((e) => e.trim().toLowerCase()).filter(Boolean);
    if (adminEmails.length && adminEmails.includes((decoded.email || "").toLowerCase())) return true;
    return decoded.admin === true;
  })();
  if (!isAdmin) { res.status(403).json({ error: "Forbidden" }); return; }

  const { orderId, userId, type } = req.query;
  if (!orderId || !userId || !["interior", "cover"].includes(type)) {
    res.status(400).json({ error: "orderId, userId, and type (interior|cover) are required" });
    return;
  }

  const orderSnap = await db.collection("users").doc(userId).collection("orders").doc(orderId).get();
  if (!orderSnap.exists) { res.status(404).json({ error: "Order not found" }); return; }
  const orderData = orderSnap.data() || {};

  const storagePath = type === "cover"
    ? orderData.coverPdfStoragePath
    : orderData.interiorPdfStoragePath;

  if (!storagePath) {
    res.status(404).json({ error: `No ${type} PDF storage path on order` });
    return;
  }

  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) { res.status(404).json({ error: `${type} PDF not found in storage` }); return; }

  const filename = type === "cover" ? "cover.pdf" : "interior.pdf";
  res.set("Content-Type", "application/pdf");
  res.set("Content-Disposition", `attachment; filename="${filename}"`);
  file.createReadStream().pipe(res);
});

exports.generateBookVersionPdf = onRequest({ timeoutSeconds: 300, memory: "4GiB" }, async (req, res) => {
  if (req.method !== "POST") {
    return jsonError(res, 405, "Method not allowed");
  }

  let decoded;
  try {
    decoded = await verifyUser(req);
  } catch (error) {
    return jsonError(res, 401, `Unauthorized: ${error.message}`);
  }

  const userId = decoded.uid;
  const bookVersionId = (req.body && req.body.bookVersionId) || "";
  const forceRegenerate = Boolean(req.body && req.body.forceRegenerate);
  if (!bookVersionId) {
    return jsonError(res, 400, "bookVersionId is required");
  }

  const docRef = db.collection("users").doc(userId).collection("bookVersions").doc(bookVersionId);
  const snapshot = await docRef.get();
  if (!snapshot.exists) {
    return jsonError(res, 404, "bookVersionId not found");
  }

  const record = snapshot.data() || {};
  if (!forceRegenerate
    && record.renderStatus === "rendered"
    && record.pdfURL
    && !mustAbortPdfPackagingForMissingCoverUrl(record)
  ) {
    return res.status(200).json({
      status: "rendered",
      pdfURL: record.pdfURL,
      pdfStoragePath: record.pdfStoragePath || null,
      renderDurationMs: record.renderDurationMs || null,
      pdfBytes: record.pdfBytes || null,
      message: "Already rendered"
    });
  }

  const pages = Array.isArray(record.pages) ? [...record.pages] : [];
  pages.sort((a, b) => (a.pageIndex || 0) - (b.pageIndex || 0));
  if (!pages.length) {
    await docRef.set({
      renderStatus: "failed",
      renderError: "No pages available for PDF packaging",
      renderAttemptCount: (record.renderAttemptCount || 0) + 1,
      renderedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    return jsonError(res, 400, "No pages available for PDF packaging");
  }

  if (mustAbortPdfPackagingForMissingCoverUrl(record)) {
    const { exhausted, nextCount } = nextCoverPreconditionAttemptMeta(record);
    if (exhausted) {
      await docRef.set(
        {
          renderStatus: "failed",
          renderError: "exhausted cover-precondition retries; client must fix cover and retry",
          renderAttemptCount: nextCount,
          renderedAt: admin.firestore.FieldValue.serverTimestamp(),
          pdfURL: admin.firestore.FieldValue.delete(),
          pdfStoragePath: admin.firestore.FieldValue.delete()
        },
        { merge: true }
      );
      return res.status(200).json({
        status: COVER_PRECONDITION_EXHAUSTED_STATUS,
        message: "coverURL precondition failed too many times",
        renderError: "exhausted cover-precondition retries; client must fix cover and retry"
      });
    }
    await docRef.set(
      {
        renderStatus: "pending",
        renderError: "missing cover; client must run regenerateCoverDesign",
        renderAttemptCount: nextCount,
        renderedAt: admin.firestore.FieldValue.serverTimestamp(),
        pdfURL: admin.firestore.FieldValue.delete(),
        pdfStoragePath: admin.firestore.FieldValue.delete()
      },
      { merge: true }
    );
    return jsonError(res, 409, "coverURL required before PDF packaging");
  }

  const trimWidthPt = Number(record.pageWidth || 612);
  const trimHeightPt = Number(record.pageHeight || 792);
  const BLEED_PT = 9;
  const widthPt = trimWidthPt + BLEED_PT * 2;
  const heightPt = trimHeightPt + BLEED_PT * 2;
  const scaleX = widthPt / trimWidthPt;
  const scaleY = heightPt / trimHeightPt;
  const scale = Math.max(scaleX, scaleY);
  const drawWidth = trimWidthPt * scale;
  const drawHeight = trimHeightPt * scale;
  const drawX = (widthPt - drawWidth) / 2;
  const drawY = (heightPt - drawHeight) / 2;

  const startMs = Date.now();
  console.log(`BOOK_RENDER_START user=${userId} version=${bookVersionId} pages=${pages.length} size=${widthPt}x${heightPt} with bleed`);

  try {
    const pdfDoc = await PDFDocument.create();
    let totalSourceBytes = 0;

    for (let i = 0; i < pages.length; i += 1) {
      const page = pages[i] || {};
      const storagePath = page.imageStoragePath || page.renderedPageStoragePath;
      if (!storagePath) {
        throw new Error(`Missing rendered page storage path at index ${i}`);
      }

      const [imageBytes] = await bucket.file(storagePath).download();
      totalSourceBytes += imageBytes.length;
      const isJpeg = storagePath.toLowerCase().endsWith(".jpg") || storagePath.toLowerCase().endsWith(".jpeg");
      const embeddedImage = isJpeg
        ? await pdfDoc.embedJpg(imageBytes)
        : await pdfDoc.embedPng(imageBytes);
      const pdfPage = pdfDoc.addPage([widthPt, heightPt]);
      pdfPage.drawImage(embeddedImage, {
        x: drawX,
        y: drawY,
        width: drawWidth,
        height: drawHeight
      });
    }

    const pdfBytes = await pdfDoc.save();
    const pdfStoragePath = `users/${userId}/bookVersions/${bookVersionId}/book.pdf`;
    const file = bucket.file(pdfStoragePath);
    const downloadToken = crypto.randomUUID();
    await file.save(Buffer.from(pdfBytes), {
      metadata: {
        contentType: "application/pdf",
        metadata: {
          firebaseStorageDownloadTokens: downloadToken
        }
      },
      resumable: false
    });
    const encodedPath = encodeURIComponent(pdfStoragePath);
    const pdfURL = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${downloadToken}`;

    const renderDurationMs = Date.now() - startMs;
    const updates = {
      renderStatus: "rendered",
      renderError: admin.firestore.FieldValue.delete(),
      renderAttemptCount: (record.renderAttemptCount || 0) + 1,
      renderedAt: admin.firestore.FieldValue.serverTimestamp(),
      pdfStoragePath,
      pdfURL,
      pdfPageCount: pages.length,
      renderDurationMs,
      totalPngBytes: totalSourceBytes,
      pdfBytes: pdfBytes.length
    };
    await docRef.set(updates, { merge: true });

    console.log(`BOOK_RENDER_SUCCESS user=${userId} version=${bookVersionId} sourceBytes=${totalSourceBytes} pdfBytes=${pdfBytes.length} durationMs=${renderDurationMs}`);

    return res.status(200).json({
      status: "rendered",
      pdfURL,
      pdfStoragePath,
      renderDurationMs,
      pdfBytes: pdfBytes.length,
      message: "PDF generated successfully"
    });
  } catch (error) {
    console.error(`BOOK_RENDER_FAILED user=${userId} version=${bookVersionId}:`, error);
    await docRef.set({
      renderStatus: "failed",
      renderError: String(error.message || error),
      renderAttemptCount: (record.renderAttemptCount || 0) + 1,
      renderedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    return jsonError(res, 500, `Failed to generate PDF: ${error.message || error}`);
  }
});

// --- Book Ordering (Stripe + Lulu) ---

/** Callable: Lulu-backed estimate for in-app checkout UI (book base + remainder as shipping & fees). */
exports.estimateCheckoutPricing = onCall(
  {
    timeoutSeconds: 60,
    secrets: [luluClientKey, luluClientSecret],
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const userId = request.auth.uid;
    const { bookVersionId, shippingAddress, shippingLevel = "MAIL", productOptionId = null } = request.data || {};
    if (!bookVersionId || !shippingAddress) {
      throw new HttpsError("invalid-argument", "bookVersionId and shippingAddress are required");
    }

    let inputs;
    try {
      inputs = await getBookVersionOrderInputs(userId, bookVersionId, productOptionId);
    } catch (e) {
      if (e instanceof HttpsError) {
        throw e;
      }
      throw new HttpsError("internal", String(e.message || e));
    }

    const addr = {
      street1: shippingAddress.street1,
      city: shippingAddress.city,
      stateCode: shippingAddress.stateCode || "",
      countryCode: shippingAddress.countryCode || "US",
      postcode: shippingAddress.postcode,
      phone: shippingAddress.phone
    };

    try {
      const pricing = await calculateMerchantPricingBreakdown({
        inputs,
        shippingAddress: addr,
        shippingLevel,
        logLabel: "estimateCheckoutPricing"
      });
      const { warnings, suggestedAddress } = extractLuluAddressFeedback(pricing.selectedCost);

      console.log(
        `estimateCheckoutPricing user=${userId} book=${bookVersionId} level=${shippingLevel} ` +
        `luluTotal=${pricing.selectedCost.total_cost_incl_tax} ` +
        `bookBaseCents=${pricing.bookBaseCents} shippingCents=${pricing.shippingCents} ` +
        `merchantTotalCents=${pricing.estimatedTotalCents}`
      );

      return {
        bookBaseCents: pricing.bookBaseCents,
        shippingCents: pricing.shippingCents,
        estimatedTotalCents: pricing.estimatedTotalCents,
        currency: "usd",
        pageCount: inputs.pageCount,
        selectedProductOptionId: inputs.selectedOption.optionId,
        selectedPodPackageId: inputs.selectedOption.podPackageId,
        selectedProductTitle: inputs.selectedOption.title,
        productOptions: inputs.productOptions.map((o) => ({
          optionId: o.optionId,
          title: o.title,
          subtitle: o.subtitle,
          minPages: o.minPages,
          maxPages: o.maxPages,
          available: o.available,
          unavailableReason: o.unavailableReason
        })),
        marginPercent: inputs.marginPercent,
        luluTotalCostInclTax: pricing.selectedCost.total_cost_incl_tax || null,
        luluShippingCostInclTax: pricing.luluShippingCostInclTax,
        selectedLineItemCostInclTax: pricing.selectedLineItemCostInclTax,
        hardcoverReferenceLineItemCostInclTax: pricing.hardcoverReferenceLineItemCostInclTax,
        hardcoverReferencePageCount: pricing.hardcoverReferencePageCount,
        pricingFloorApplied: Boolean(pricing.pricingFloorApplied),
        luluCurrency: pricing.selectedCost.currency || null,
        warnings,
        suggestedAddress,
        fallback: false
      };
    } catch (err) {
      console.warn("estimateCheckoutPricing Lulu error:", err.message);
      return {
        bookBaseCents: inputs.baseCents,
        shippingCents: 0,
        estimatedTotalCents: inputs.baseCents,
        currency: "usd",
        pageCount: inputs.pageCount,
        selectedProductOptionId: inputs.selectedOption.optionId,
        selectedPodPackageId: inputs.selectedOption.podPackageId,
        selectedProductTitle: inputs.selectedOption.title,
        productOptions: inputs.productOptions.map((o) => ({
          optionId: o.optionId,
          title: o.title,
          subtitle: o.subtitle,
          minPages: o.minPages,
          maxPages: o.maxPages,
          available: o.available,
          unavailableReason: o.unavailableReason
        })),
        marginPercent: inputs.marginPercent,
        luluTotalCostInclTax: null,
        luluShippingCostInclTax: null,
        pricingFloorApplied: true,
        luluCurrency: null,
        warnings: [{ type: "lulu_error", code: "", path: "", message: String(err.message || err) }],
        ...luluFallbackDiagnostics(err),
        suggestedAddress: null,
        fallback: true
      };
    }
  }
);

/** Callable: multi-item cart estimate (per-line live Lulu + merchant formula). */
exports.estimateCartCheckoutPricing = onCall(
  {
    timeoutSeconds: 120,
    secrets: [luluClientKey, luluClientSecret],
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const userId = request.auth.uid;
    const { items, shippingAddress, shippingLevel = "MAIL" } = request.data || {};
    if (!Array.isArray(items) || items.length === 0 || !shippingAddress) {
      throw new HttpsError("invalid-argument", "items[] and shippingAddress are required");
    }
    if (items.length > 25) {
      throw new HttpsError("invalid-argument", "Cart cannot exceed 25 lines");
    }

    const allWarnings = [];
    let suggestedAddress = null;
    const lines = [];
    let subtotalCents = 0;
    /** For fallback shipping-method estimates if /shipping-options/ fails */
    let firstLineForShippingMethods = null;
    let firstLineQuantity = 1;
    /** Full cart: every resolved line’s pod package, pages, qty for aggregate shipping-options */
    const cartLineItemsForShippingOptions = [];

    for (let i = 0; i < items.length; i += 1) {
      const row = items[i] || {};
      const bookVersionId = row.bookVersionId;
      const productOptionId = row.productOptionId || null;
      const quantity = Math.min(99, Math.max(1, parseInt(row.quantity, 10) || 1));
      if (!bookVersionId) {
        throw new HttpsError("invalid-argument", `items[${i}].bookVersionId is required`);
      }

      try {
        const rowLabel = `estimateCartCheckoutPricing:${i}:${bookVersionId}`;
        const resolved = await pricingForCartLine(
          userId,
          bookVersionId,
          productOptionId,
          shippingAddress,
          shippingLevel,
          rowLabel,
          quantity
        );
        for (const w of resolved.warnings) {
          allWarnings.push(w);
        }
        if (!suggestedAddress && resolved.suggestedAddress) {
          suggestedAddress = resolved.suggestedAddress;
        }
        if (!firstLineForShippingMethods) {
          firstLineForShippingMethods = resolved;
          firstLineQuantity = quantity;
        }
        cartLineItemsForShippingOptions.push({
          podPackageId: resolved.inputs.podPackageId,
          pageCount: resolved.inputs.pageCount,
          quantity
        });
        const lineBook = resolved.pricing.bookBaseCents;
        const lineShip = resolved.pricing.shippingCents;
        const lineTotal = resolved.pricing.estimatedTotalCents;
        subtotalCents += lineTotal;
        const unitBook = quantity > 0 ? Math.round(lineBook / quantity) : lineBook;
        const unitShip = quantity > 0 ? Math.round(lineShip / quantity) : lineShip;
        const unitTot = quantity > 0 ? Math.round(lineTotal / quantity) : lineTotal;
        lines.push({
          bookVersionId,
          productOptionId: resolved.inputs.selectedOption.optionId,
          productTitle: resolved.inputs.selectedOption.title,
          quantity,
          lineBookBaseCents: lineBook,
          lineShippingCents: lineShip,
          unitBookBaseCents: unitBook,
          unitShippingCents: unitShip,
          unitTotalCents: unitTot,
          lineTotalCents: lineTotal,
          pageCount: resolved.inputs.pageCount
        });
      } catch (err) {
        console.warn("estimateCartCheckoutPricing line error:", err.message);
        if (err instanceof HttpsError) {
          throw err;
        }
        throw new HttpsError("failed-precondition", String(err.message || err));
      }
    }

    console.log(
      `estimateCartCheckoutPricing user=${userId} lines=${lines.length} total=${subtotalCents}`
    );

    let shippingMethods = [];
    if (cartLineItemsForShippingOptions.length > 0) {
      try {
        shippingMethods = await estimateLuluShippingMethodsForCart({
          lineItems: cartLineItemsForShippingOptions,
          shippingAddress,
          logLabel: "estimateCartCheckoutPricing"
        });
      } catch (err) {
        console.warn("estimateCartCheckoutPricing shipping-options failed:", String(err.message || err));
      }
    }
    if (shippingMethods.length === 0 && firstLineForShippingMethods) {
      try {
        shippingMethods = await estimateLuluShippingMethodsForLine({
          selectedCost: firstLineForShippingMethods.pricing.selectedCost,
          selectedShippingLevel: shippingLevel,
          podPackageId: firstLineForShippingMethods.inputs.podPackageId,
          pageCount: firstLineForShippingMethods.inputs.pageCount,
          shippingAddress,
          logLabel: "estimateCartCheckoutPricing:fallbackFirstLine",
          quantity: firstLineQuantity
        });
      } catch (err) {
        console.warn("estimateCartCheckoutPricing shippingMethods fallback failed:", String(err.message || err));
      }
    }

    const booksSubtotalCents = lines.reduce((s, l) => s + l.lineBookBaseCents, 0);
    // Each cart line ships as its own separate Lulu print job/package, so the estimate must be the
    // SUM of each line's own Lulu shipping quote (already computed per line above) — see the matching
    // comment in buildCartCheckoutResolved for why a single combined-shipment quote undercharges.
    const summedLineShippingCents = sumCartLineShippingCents(lines.map((l) => l.lineShippingCents));
    const orderShippingCents = summedLineShippingCents;

    const adjustedLines = lines.map((l) => {
      const unitTot = l.quantity > 0 ? Math.round(l.lineBookBaseCents / l.quantity) : l.lineBookBaseCents;
      return {
        ...l,
        lineShippingCents: 0,
        unitShippingCents: 0,
        lineTotalCents: l.lineBookBaseCents,
        unitTotalCents: unitTot
      };
    });
    const estimatedTotalCents = booksSubtotalCents + orderShippingCents;

    console.log(
      `estimateCartCheckoutPricing user=${userId} books=${booksSubtotalCents} ` +
      `orderShip=${orderShippingCents} total=${estimatedTotalCents} (was subtotal ${subtotalCents})`
    );

    return {
      lines: adjustedLines,
      booksSubtotalCents,
      orderShippingCents,
      subtotalCents: estimatedTotalCents,
      estimatedTotalCents,
      currency: "usd",
      shippingLevel,
      shippingMethods,
      warnings: allWarnings,
      suggestedAddress,
      fallback: false
    };
  }
);

/** Callable: precompute cart quote for fast checkout (Lulu once; Stripe later). */
exports.prepareCartCheckoutQuote = onCall(
  {
    timeoutSeconds: 120,
    secrets: [luluClientKey, luluClientSecret],
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    const startMs = Date.now();
    const elapsedMs = () => Date.now() - startMs;
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const userId = request.auth.uid;
    const debugId = `qprep_${Date.now()}_${crypto.randomBytes(3).toString("hex")}`;
    const { items, shippingAddress, shippingLevel = "MAIL", clientPayloadHash } = request.data || {};
    if (!Array.isArray(items) || items.length === 0 || !shippingAddress) {
      throw new HttpsError("invalid-argument", "items[] and shippingAddress are required");
    }
    if (items.length > 25) {
      throw new HttpsError("invalid-argument", "Cart cannot exceed 25 lines");
    }

    console.log(
      JSON.stringify({
        msg: "prepareCartCheckoutQuote:start",
        userId,
        debugId,
        stage: "start",
        itemCount: items.length,
        shippingLevel: shippingLevel || "MAIL",
        elapsedMs: elapsedMs()
      })
    );

    const cartHash = computeCartCheckoutPayloadHash(items, shippingAddress, shippingLevel);
    if (clientPayloadHash && String(clientPayloadHash) !== cartHash) {
      throw new HttpsError(
        "failed-precondition",
        "Cart or address changed since quote was requested. Refresh pricing and try again.",
        { debugId, stage: "hash_mismatch", cartHash }
      );
    }

    const built = await buildCartCheckoutResolved(
      userId,
      items,
      shippingAddress,
      shippingLevel,
      "prepareCartCheckoutQuote"
    );

    console.log(
      JSON.stringify({
        msg: "prepareCartCheckoutQuote:resolved",
        userId,
        debugId,
        stage: "line_pricing_done",
        booksSubtotalCents: built.booksSubtotalCents,
        orderShippingCents: built.orderShippingCents,
        totalCents: built.totalCents,
        elapsedMs: elapsedMs()
      })
    );

    const shippingMethods = await estimateShippingMethodsForCartSnapshot({
      cartLineItemsForShippingOptions: built.cartLineItemsForShippingOptions,
      shippingAddress,
      shippingLevel,
      firstResolvedLine: built.firstResolvedLine,
      firstLineQuantity: built.firstLineQuantity,
      logLabel: "prepareCartCheckoutQuote"
    });

    const adjustedLines = built.resolvedItems.map((item) => {
      const qty = item.quantity || 1;
      const lineBook = item.lineBookBaseCents;
      const unitTot = qty > 0 ? Math.round(lineBook / qty) : lineBook;
      return {
        bookVersionId: item.bookVersionId,
        productOptionId: item.productOptionId,
        productTitle: item.productTitle,
        quantity: qty,
        lineBookBaseCents: lineBook,
        lineShippingCents: 0,
        unitBookBaseCents: unitTot,
        unitShippingCents: 0,
        unitTotalCents: unitTot,
        lineTotalCents: lineBook,
        pageCount: item.pageCount
      };
    });

    const quoteId = `q_${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + CART_CHECKOUT_QUOTE_TTL_MS);

    const quoteRef = db.collection("users").doc(userId).collection("checkoutQuotes").doc(quoteId);
    await quoteRef.set({
      quoteId,
      userId,
      cartHash,
      items: normalizeCartItemsForHash(items).map((row) => ({
        bookVersionId: row.bookVersionId,
        productOptionId: row.productOptionId || null,
        quantity: row.quantity
      })),
      shippingAddress,
      shippingLevel: shippingLevel || "MAIL",
      stripeLineItems: built.stripeLineItems,
      resolvedItems: built.resolvedItems,
      booksSubtotalCents: built.booksSubtotalCents,
      orderShippingCents: built.orderShippingCents,
      totalCents: built.totalCents,
      shippingMethods,
      warnings: built.allWarnings,
      suggestedAddress: built.suggestedAddress || null,
      status: "ready",
      debugId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt
    });

    console.log(
      JSON.stringify({
        msg: "prepareCartCheckoutQuote:written",
        userId,
        debugId,
        quoteId,
        cartHash,
        totalCents: built.totalCents,
        elapsedMs: elapsedMs()
      })
    );

    return {
      quoteId,
      cartHash,
      expiresAt: { _seconds: Math.floor(expiresAt.toMillis() / 1000), _nanoseconds: 0 },
      expiresAtMillis: expiresAt.toMillis(),
      lines: adjustedLines,
      booksSubtotalCents: built.booksSubtotalCents,
      orderShippingCents: built.orderShippingCents,
      subtotalCents: built.totalCents,
      estimatedTotalCents: built.totalCents,
      currency: "usd",
      shippingLevel: shippingLevel || "MAIL",
      shippingMethods,
      warnings: built.allWarnings,
      suggestedAddress: built.suggestedAddress,
      fallback: false,
      fastCheckoutEnabled: isFastCartCheckoutEnabled()
    };
  }
);

/** Callable: create Stripe session from a prepared quote (no Lulu pricing work). */
exports.createCartCheckoutSessionFast = onCall(
  {
    timeoutSeconds: 60,
    secrets: [stripeSecretKey, luluClientKey, luluClientSecret],
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    const startMs = Date.now();
    const elapsedMs = () => Date.now() - startMs;
    if (!isFastCartCheckoutEnabled()) {
      throw new HttpsError(
        "failed-precondition",
        "Fast checkout is disabled. Use the standard checkout action.",
        { code: "fast_checkout_disabled" }
      );
    }
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in to order books");
    }
    const userId = request.auth.uid;
    const debugId = `ccf_${Date.now()}_${crypto.randomBytes(3).toString("hex")}`;
    let stage = "input_validation";
    const {
      quoteId,
      clientEstimatedTotalCents,
      cartHash: clientCartHash,
      checkoutInstanceId: rawCheckoutInstanceId,
      clientCorrelationId: rawClientCorrelationId,
      idempotencyKey: legacyClientKey
    } = request.data || {};
    if (!quoteId || typeof quoteId !== "string") {
      throw new HttpsError("invalid-argument", "quoteId is required");
    }
    const resumeCheckoutId = sanitizeCheckoutInstanceId(rawCheckoutInstanceId);
    const clientCorrelationId =
      sanitizeClientCorrelationId(rawClientCorrelationId) ||
      sanitizeClientCorrelationId(legacyClientKey);

    const seqRef = userCheckoutSeqRef(userId);
    const refCheckoutAttempt = (id) =>
      db.collection("users").doc(userId).collection("checkoutAttempts").doc(id);

    const openCheckout = await db.runTransaction(async (transaction) => {
      let checkoutId;
      if (resumeCheckoutId) {
        // Resume: only read the attempt doc, then write — no seq doc involved.
        checkoutId = resumeCheckoutId;
        const ar = refCheckoutAttempt(checkoutId);
        const attemptSnap = await transaction.get(ar);
        if (attemptSnap.exists) {
          const d = attemptSnap.data() || {};
          if (d.stripeSessionId && d.checkoutUrl && d.cartOrderGroupId) {
            return {
              replay: true,
              checkoutUrl: d.checkoutUrl,
              sessionId: d.stripeSessionId,
              cartOrderGroupId: d.cartOrderGroupId,
              totalCents: d.totalCents || 0,
              checkoutId
            };
          }
          const startedMs = d.startedAt && d.startedAt.toMillis ? d.startedAt.toMillis() : 0;
          if (d.status === "processing" && startedMs && Date.now() - startedMs < 120000) {
            throw new HttpsError(
              "resource-exhausted",
              "Checkout is already in progress. Wait a moment and try again.",
              { debugId, stage: "idempotency_in_flight", checkoutInstanceId: checkoutId }
            );
          }
        } else {
          throw new HttpsError("invalid-argument", "Unknown checkoutInstanceId.", {
            checkoutInstanceId: resumeCheckoutId,
            debugId,
            stage: "resume_not_found"
          });
        }

        const processingPayload = {
          status: "processing",
          quoteId,
          userId,
          debugId,
          checkoutInstanceId: checkoutId,
          startedAt: admin.firestore.FieldValue.serverTimestamp()
        };
        if (clientCorrelationId) {
          processingPayload.clientCorrelationId = clientCorrelationId;
        }
        transaction.set(refCheckoutAttempt(checkoutId), processingPayload, { merge: true });
        return { replay: false, checkoutId };
      }

      // New book{N}: read seq + attempt BEFORE any writes (Firestore rule).
      const cSnap = await transaction.get(seqRef);
      const prev = cSnap.exists && cSnap.data() ? Number(cSnap.data().next) || 0 : 0;
      const next = prev + 1;
      checkoutId = `book${next}`;
      const ar = refCheckoutAttempt(checkoutId);
      const attemptSnap = await transaction.get(ar);
      if (attemptSnap.exists) {
        const d = attemptSnap.data() || {};
        if (d.stripeSessionId && d.checkoutUrl && d.cartOrderGroupId) {
          return {
            replay: true,
            checkoutUrl: d.checkoutUrl,
            sessionId: d.stripeSessionId,
            cartOrderGroupId: d.cartOrderGroupId,
            totalCents: d.totalCents || 0,
            checkoutId
          };
        }
        const startedMs = d.startedAt && d.startedAt.toMillis ? d.startedAt.toMillis() : 0;
        if (d.status === "processing" && startedMs && Date.now() - startedMs < 120000) {
          throw new HttpsError(
            "resource-exhausted",
            "Checkout is already in progress. Wait a moment and try again.",
            { debugId, stage: "idempotency_in_flight", checkoutInstanceId: checkoutId }
          );
        }
      }

      const processingPayload = {
        status: "processing",
        quoteId,
        userId,
        debugId,
        checkoutInstanceId: checkoutId,
        startedAt: admin.firestore.FieldValue.serverTimestamp()
      };
      if (clientCorrelationId) {
        processingPayload.clientCorrelationId = clientCorrelationId;
      }
      transaction.set(
        seqRef,
        { next, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
      transaction.set(ar, processingPayload, { merge: true });
      return { replay: false, checkoutId };
    });

    if (openCheckout.replay) {
      console.log(
        JSON.stringify({
          msg: "createCartCheckoutSessionFast:idempotent_replay",
          userId,
          debugId,
          checkoutInstanceId: openCheckout.checkoutId,
          stage: "idempotent_replay",
          fallback: false,
          elapsedMs: elapsedMs()
        })
      );
      return {
        checkoutUrl: openCheckout.checkoutUrl,
        sessionId: openCheckout.sessionId,
        cartOrderGroupId: openCheckout.cartOrderGroupId,
        checkoutInstanceId: openCheckout.checkoutId,
        totalCents: openCheckout.totalCents,
        idempotentReplay: true
      };
    }

    const checkoutId = openCheckout.checkoutId;
    const attemptRef = db.collection("users").doc(userId).collection("checkoutAttempts").doc(checkoutId);

    const quoteRef = db.collection("users").doc(userId).collection("checkoutQuotes").doc(quoteId);
    const quoteSnap = await quoteRef.get();
    if (!quoteSnap.exists) {
      await attemptRef.set(
        { status: "failed", failedStage: "quote_load", error: "quote_not_found", updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
      throw new HttpsError("not-found", "Checkout quote expired or invalid. Refresh pricing and try again.", {
        debugId,
        stage: "quote_load"
      });
    }

    const quote = quoteSnap.data() || {};
    if (quote.userId && quote.userId !== userId) {
      throw new HttpsError("permission-denied", "Quote does not belong to this user");
    }
    if (quote.status && quote.status !== "ready") {
      throw new HttpsError("failed-precondition", "Quote is no longer valid.", { debugId, stage: "quote_status" });
    }
    const exp = quote.expiresAt;
    const expMs = exp && exp.toMillis ? exp.toMillis() : 0;
    if (expMs && Date.now() > expMs) {
      await quoteRef.set({ status: "expired", updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      await attemptRef.set(
        { status: "failed", failedStage: "quote_expired", updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
      throw new HttpsError(
        "failed-precondition",
        "Checkout quote expired. Refresh pricing and try again.",
        { debugId, stage: "quote_expired" }
      );
    }

    if (clientCartHash && quote.cartHash && String(clientCartHash) !== quote.cartHash) {
      await attemptRef.set(
        { status: "failed", failedStage: "hash_mismatch", updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
      throw new HttpsError(
        "failed-precondition",
        "Cart changed since quote. Refresh pricing and try again.",
        { debugId, stage: "hash_mismatch" }
      );
    }

    const stripeLineItems = quote.stripeLineItems;
    const resolvedItems = quote.resolvedItems;
    const shippingAddress = quote.shippingAddress;
    const shippingLevel = quote.shippingLevel || "MAIL";
    const booksSubtotalCents = quote.booksSubtotalCents || 0;
    const orderShippingCents = quote.orderShippingCents || 0;
    const totalCents = quote.totalCents || 0;

    if (!Array.isArray(stripeLineItems) || stripeLineItems.length === 0 || !Array.isArray(resolvedItems)) {
      throw new HttpsError(
        "failed-precondition",
        "Quote data is incomplete. Pull to refresh the estimate, then try checkout again.",
        { debugId, stage: "quote_incomplete" }
      );
    }

    if (clientEstimatedTotalCents != null && Number.isFinite(Number(clientEstimatedTotalCents))) {
      const cli = Math.round(Number(clientEstimatedTotalCents));
      if (cli !== totalCents) {
        console.warn(`createCartCheckoutSessionFast pricing drift user=${userId} client=${cli} server=${totalCents}`);
      }
    }

    stage = "pending_checkout_write";
    const cartOrderGroupId = checkoutId;
    const pendingRef = db.collection("users").doc(userId).collection("pendingCartCheckouts").doc(cartOrderGroupId);

    await pendingRef.set({
      cartOrderGroupId,
      userId,
      items: resolvedItems,
      shippingAddress,
      shippingLevel,
      totalCents,
      booksSubtotalCents,
      orderShippingCents,
      status: "pending_stripe",
      quoteId,
      idempotencyKey: checkoutId,
      checkoutAttemptDocId: checkoutId,
      checkoutPath: "fast",
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log(
      JSON.stringify({
        msg: "createCartCheckoutSessionFast:pending_written",
        userId,
        debugId,
        quoteId,
        cartOrderGroupId,
        totalCents,
        lineItemsForStripe: stripeLineItems.length,
        elapsedMs: elapsedMs()
      })
    );

    const stripe = createStripeClient({ maxNetworkRetries: 1, timeoutMs: 20 * 1000 });
    let session;
    try {
      stage = "stripe_session_create";
      console.log(
        JSON.stringify({
          msg: "createCartCheckoutSessionFast:stripe_session_create",
          userId,
          debugId,
          cartOrderGroupId,
          totalCents,
          elapsedMs: elapsedMs()
        })
      );
      session = await createStripeCheckoutSessionWithRetry(
        stripe,
        {
          mode: "payment",
          payment_method_types: ["card"],
          line_items: stripeLineItems,
          success_url: `memoirai://order-complete?session_id={CHECKOUT_SESSION_ID}`,
          cancel_url: "memoirai://order-cancelled",
          metadata: {
            cartOrderGroupId,
            userId,
            shippingLevel: shippingLevel || "MAIL",
            totalCents: String(totalCents),
            quoteId: quoteId || ""
          },
          customer_email: request.auth.token?.email || undefined,
          payment_intent_data: {
            receipt_email: request.auth.token?.email || undefined
          }
        },
        "createCartCheckoutSessionFast",
        `fast_${checkoutId}`
      );
    } catch (err) {
      const stripeMessage = String(err?.message || err || "unknown");
      const transient = isLikelyTransientStripeError(err);
      console.error(
        "createCartCheckoutSessionFast stripe session create failed:",
        {
          userId,
          debugId,
          cartOrderGroupId,
          elapsedMs: elapsedMs(),
          totalCents,
          transient,
          message: stripeMessage
        }
      );
      await pendingRef.set(
        {
          status: "stripe_create_failed",
          debugId,
          failedStage: stage,
          elapsedMs: elapsedMs(),
          stripeError: stripeMessage,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        { merge: true }
      );
      await attemptRef.set(
        {
          status: "failed",
          failedStage: stage,
          stripeError: stripeMessage,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        { merge: true }
      );
      if (transient) {
        throw new HttpsError(
          "unavailable",
          "Stripe is temporarily unreachable. Please try again in a moment.",
          {
            debugId,
            cartOrderGroupId,
            stage,
            transient,
            stripeType: err?.type || null,
            stripeCode: err?.code || null,
            stripeMessage
          }
        );
      }
      throwStripeCheckoutSessionHttpsError(err, {
        debugId,
        cartOrderGroupId,
        stage,
        transient
      });
    }

    await pendingRef.update({
      stripeSessionId: session.id,
      elapsedMs: elapsedMs(),
      finalStage: "stripe_session_created"
    });

    await quoteRef.set(
      {
        status: "consumed",
        consumedAt: admin.firestore.FieldValue.serverTimestamp(),
        cartOrderGroupId,
        stripeSessionId: session.id
      },
      { merge: true }
    );

    await attemptRef.set(
      {
        status: "completed",
        cartOrderGroupId,
        stripeSessionId: session.id,
        checkoutUrl: session.url,
        totalCents,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        items: resolvedItems,
        paymentStatus: "pending",
        checkoutPath: "fast"
      },
      { merge: true }
    );

    console.log(
      JSON.stringify({
        msg: "createCartCheckoutSessionFast:success",
        userId,
        debugId,
        quoteId,
        cartOrderGroupId,
        stage: "complete",
        totalCents,
        elapsedMs: elapsedMs()
      })
    );

    return {
      checkoutUrl: session.url,
      sessionId: session.id,
      cartOrderGroupId,
      checkoutInstanceId: checkoutId,
      totalCents,
      idempotentReplay: false
    };
  }
);

/** Proxy Google Places Autocomplete (Places API New — server-side key). */
exports.autocompleteAddress = onCall(
  {
    timeoutSeconds: 30,
    secrets: [googlePlacesApiKey]
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const { query, sessionToken, countryCode } = request.data || {};
    const q = String(query || "").trim();
    if (q.length < 3) {
      return { predictions: [], status: "ZERO_RESULTS" };
    }
    const key = googlePlacesApiKey.value();
    if (!key) {
      throw new HttpsError("failed-precondition", "Address search is not configured");
    }

    try {
      const { predictions, status } = await googlePlacesAutocompleteNew({
        query: q,
        countryCode,
        sessionToken,
        apiKey: key
      });
      return { predictions, status };
    } catch (e) {
      if (e instanceof HttpsError) {
        throw e;
      }
      console.error("Places autocomplete (new):", e.message || e);
      throw new HttpsError("failed-precondition", String(e.message || e));
    }
  }
);

/** Place Details (Places API New) -> fields for ShippingAddress. */
exports.resolveAddressPlace = onCall(
  {
    timeoutSeconds: 30,
    secrets: [googlePlacesApiKey]
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const { placeId, sessionToken } = request.data || {};
    if (!placeId) {
      throw new HttpsError("invalid-argument", "placeId is required");
    }
    const key = googlePlacesApiKey.value();
    if (!key) {
      throw new HttpsError("failed-precondition", "Address search is not configured");
    }

    try {
      return await googlePlacesGetPlaceNew({ placeId, sessionToken, apiKey: key });
    } catch (e) {
      if (e instanceof HttpsError) {
        throw e;
      }
      console.error("Places details (new):", e.message || e);
      throw new HttpsError("failed-precondition", String(e.message || e));
    }
  }
);

exports.createCheckoutSession = onCall(
  {
    timeoutSeconds: 60,
    secrets: [stripeSecretKey, luluClientKey, luluClientSecret],
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in to order a book");
    }
    const userId = request.auth.uid;
    const debugId = `cs_${Date.now()}_${crypto.randomBytes(3).toString("hex")}`;
    const { bookVersionId, shippingAddress, shippingLevel = "MAIL", clientEstimatedTotalCents, productOptionId = null } = request.data || {};
    if (!bookVersionId || !shippingAddress) {
      throw new HttpsError("invalid-argument", "bookVersionId and shippingAddress are required");
    }

    let inputs;
    try {
      inputs = await getBookVersionOrderInputs(userId, bookVersionId, productOptionId);
    } catch (e) {
      if (e instanceof HttpsError) {
        throw e;
      }
      throw new HttpsError("internal", String(e.message || e));
    }

    const { record, pageCount, baseCents, marginPercent, isLandscape, selectedOption } = inputs;
    const pdfStoragePath = record.pdfStoragePath;
    const coverStoragePath = record.coverStoragePath;
    const dimensions = isLandscape ? "11x8.5\"" : "8.5x11\"";

    let totalCents = baseCents;
    let pricingFallbackReason = null;
    let pricingFallbackPhase = null;
    let pricingFallbackStatusCode = null;
    let pricingFallbackDetail = null;
    try {
      const pricing = await calculateMerchantPricingBreakdown({
        inputs,
        shippingAddress: {
          street1: shippingAddress.street1,
          city: shippingAddress.city,
          stateCode: shippingAddress.stateCode || "",
          countryCode: shippingAddress.countryCode || "US",
          postcode: shippingAddress.postcode,
          phone: shippingAddress.phone
        },
        shippingLevel,
        logLabel: "createCheckoutSession"
      });
      totalCents = pricing.estimatedTotalCents;
      if (clientEstimatedTotalCents != null && Number.isFinite(Number(clientEstimatedTotalCents))) {
        const cli = Math.round(Number(clientEstimatedTotalCents));
        if (cli !== totalCents) {
          console.warn(
            `createCheckoutSession pricing drift user=${userId} book=${bookVersionId} ` +
            `clientEstimate=${cli} serverTotal=${totalCents} lulu=${pricing.selectedCost.total_cost_incl_tax}`
          );
        }
      }
    } catch (err) {
      console.warn("Lulu cost calculation failed, using base price:", err.message);
      const diag = luluFallbackDiagnostics(err);
      pricingFallbackReason = diag.fallbackReason;
      pricingFallbackPhase = diag.fallbackPhase;
      pricingFallbackStatusCode = diag.fallbackStatusCode;
      pricingFallbackDetail = diag.fallbackDetail;
      totalCents = baseCents;
    }

    const stripe = createStripeClient({ maxNetworkRetries: 1, timeoutMs: 20 * 1000 });
    let session;
    try {
      console.log(JSON.stringify({ msg: "createCheckoutSession:stripe_session_create", userId, debugId, totalCents }));
      session = await createStripeCheckoutSessionWithRetry(stripe, {
        mode: "payment",
        payment_method_types: ["card"],
        line_items: [
          {
            price_data: {
              currency: "usd",
              product_data: {
                name: "MemoirAI Printed Book",
                description: `${dimensions} ${selectedOption.title}, Full Color, Matte. ${pageCount} pages.`
              },
              unit_amount: totalCents
            },
            quantity: 1
          }
        ],
        success_url: `memoirai://order-complete?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: "memoirai://order-cancelled",
        metadata: {
          bookVersionId,
          userId,
          shippingAddress: JSON.stringify(shippingAddress),
          shippingLevel,
          totalCents: String(totalCents),
          coverStoragePath,
          pdfStoragePath,
          pricingFallbackReason: pricingFallbackReason || "",
          pricingFallbackPhase: pricingFallbackPhase || "",
          pricingFallbackStatusCode: pricingFallbackStatusCode != null ? String(pricingFallbackStatusCode) : "",
          pricingFallbackDetail: pricingFallbackDetail || "",
          selectedProductOptionId: selectedOption.optionId,
          selectedPodPackageId: selectedOption.podPackageId
        },
        customer_email: request.auth.token?.email || undefined,
        payment_intent_data: {
          receipt_email: request.auth.token?.email || undefined
        }
      }, "createCheckoutSession");
    } catch (err) {
      const stripeMessage = String(err?.message || err || "unknown");
      const transient = isLikelyTransientStripeError(err);
      console.error("createCheckoutSession stripe session create failed:", {
        userId,
        debugId,
        bookVersionId,
        totalCents,
        shippingLevel,
        code: err?.code || null,
        type: err?.type || null,
        transient,
        message: stripeMessage
      }, "createCheckoutSession", `single_${debugId}`);
      if (transient) {
        throw new HttpsError(
          "unavailable",
          "Stripe is temporarily unreachable. Please try again in a moment.",
          {
            debugId,
            stage: "stripe_session_create",
            transient,
            stripeType: err?.type || null,
            stripeCode: err?.code || null,
            stripeMessage
          }
        );
      }
      throwStripeCheckoutSessionHttpsError(err, {
        debugId,
        stage: "stripe_session_create",
        transient
      });
    }

    return { checkoutUrl: session.url, sessionId: session.id };
  }
);

/** Callable: Stripe checkout for multiple books (one session, multiple line items). */
exports.createCartCheckoutSession = onCall(
  {
    timeoutSeconds: 120,
    secrets: [stripeSecretKey, luluClientKey, luluClientSecret],
    enforceAppCheck: isAppCheckEnforced()
  },
  async (request) => {
    const startMs = Date.now();
    const elapsedMs = () => Date.now() - startMs;
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in to order books");
    }
    const userId = request.auth.uid;
    const debugId = `ccs_${Date.now()}_${crypto.randomBytes(3).toString("hex")}`;
    let stage = "input_validation";
    const { items, shippingAddress, shippingLevel = "MAIL", clientEstimatedTotalCents } = request.data || {};
    if (!Array.isArray(items) || items.length === 0 || !shippingAddress) {
      throw new HttpsError("invalid-argument", "items[] and shippingAddress are required");
    }
    if (items.length > 25) {
      throw new HttpsError("invalid-argument", "Cart cannot exceed 25 lines");
    }

    const cartOrderGroupId = await allocateNextBookCheckoutId(userId);
    stage = "start";
    console.log(
      JSON.stringify({
        msg: "createCartCheckoutSession:start",
        userId,
        debugId,
        cartOrderGroupId,
        itemCount: items.length,
        shippingLevel: shippingLevel || "MAIL",
        elapsedMs: elapsedMs()
      })
    );
    stage = "line_pricing";
    let built;
    try {
      built = await buildCartCheckoutResolved(
        userId,
        items,
        shippingAddress,
        shippingLevel,
        "createCartCheckoutSession"
      );
    } catch (err) {
      const d = err instanceof HttpsError && err.details && typeof err.details === "object" ? err.details : {};
      console.error("createCartCheckoutSession line_pricing failed:", {
        userId,
        debugId,
        cartOrderGroupId,
        elapsedMs: elapsedMs(),
        lineIndex: d.lineIndex ?? null,
        bookVersionId: d.bookVersionId ?? null,
        code: err?.code || null,
        type: err?.type || null,
        message: String(err?.message || err || "unknown")
      });
      if (err instanceof HttpsError) {
        throw new HttpsError(err.code, err.message, {
          ...d,
          debugId,
          cartOrderGroupId,
          stage: "line_pricing"
        });
      }
      throw new HttpsError("failed-precondition", String(err?.message || err || "Line pricing failed"), {
        debugId,
        cartOrderGroupId,
        stage: "line_pricing"
      });
    }

    const { stripeLineItems, resolvedItems, booksSubtotalCents, orderShippingCents, totalCents } = built;

    if (clientEstimatedTotalCents != null && Number.isFinite(Number(clientEstimatedTotalCents))) {
      const cli = Math.round(Number(clientEstimatedTotalCents));
      if (cli !== totalCents) {
        console.warn(`createCartCheckoutSession pricing drift user=${userId} client=${cli} server=${totalCents}`);
      }
    }

    stage = "pending_checkout_write";
    const pendingRef = db.collection("users").doc(userId).collection("pendingCartCheckouts").doc(cartOrderGroupId);
    await pendingRef.set({
      cartOrderGroupId,
      userId,
      items: resolvedItems,
      shippingAddress,
      shippingLevel,
      totalCents,
      booksSubtotalCents,
      orderShippingCents,
      status: "pending_stripe",
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(
      JSON.stringify({
        msg: "createCartCheckoutSession:pending_written",
        userId,
        debugId,
        cartOrderGroupId,
        totalCents,
        lineItemsForStripe: stripeLineItems.length,
        elapsedMs: elapsedMs()
      })
    );

    const stripe = createStripeClient({ maxNetworkRetries: 1, timeoutMs: 20 * 1000 });
    let session;
    try {
      stage = "stripe_session_create";
      console.log(
        JSON.stringify({
          msg: "createCartCheckoutSession:stripe_session_create",
          userId,
          debugId,
          cartOrderGroupId,
          totalCents,
          elapsedMs: elapsedMs()
        })
      );
      session = await createStripeCheckoutSessionWithRetry(stripe, {
        mode: "payment",
        payment_method_types: ["card"],
        line_items: stripeLineItems,
        success_url: `memoirai://order-complete?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: "memoirai://order-cancelled",
        metadata: {
          cartOrderGroupId,
          userId,
          shippingLevel: shippingLevel || "MAIL",
          totalCents: String(totalCents)
        },
        customer_email: request.auth.token?.email || undefined,
        payment_intent_data: {
          receipt_email: request.auth.token?.email || undefined
        }
      }, "createCartCheckoutSession", `cart_${cartOrderGroupId}`);
    } catch (err) {
      const stripeMessage = String(err?.message || err || "unknown");
      const transient = isLikelyTransientStripeError(err);
      console.error(
        "createCartCheckoutSession stripe session create failed:",
        {
          userId,
          debugId,
          cartOrderGroupId,
          elapsedMs: elapsedMs(),
          totalCents,
          shippingLevel,
          lineCount: stripeLineItems.length,
          code: err?.code || null,
          type: err?.type || null,
          transient,
          message: stripeMessage
        }
      );
      console.error(
        `createCartCheckoutSession CORRELATION lookup Firestore: users/${userId}/pendingCartCheckouts/${cartOrderGroupId} status may be stripe_create_failed`
      );
      await pendingRef.set({
        status: "stripe_create_failed",
        debugId,
        failedStage: stage,
        elapsedMs: elapsedMs(),
        stripeError: stripeMessage,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
      if (transient) {
        throw new HttpsError(
          "unavailable",
          "Stripe is temporarily unreachable. Please try again in a moment.",
          {
            debugId,
            cartOrderGroupId,
            stage,
            transient,
            stripeType: err?.type || null,
            stripeCode: err?.code || null,
            stripeMessage
          }
        );
      }
      throwStripeCheckoutSessionHttpsError(err, {
        debugId,
        cartOrderGroupId,
        stage,
        transient
      });
    }

    await pendingRef.update({ stripeSessionId: session.id, elapsedMs: elapsedMs(), finalStage: "stripe_session_created" });

    console.log(
      JSON.stringify({
        msg: "createCartCheckoutSession:success",
        userId,
        debugId,
        cartOrderGroupId,
        stage: "complete",
        path: "legacy",
        totalCents,
        elapsedMs: elapsedMs()
      })
    );

    return { checkoutUrl: session.url, sessionId: session.id, cartOrderGroupId, totalCents };
  }
);

/**
 * Builds the ops alert subject/body for a newly paid cart checkout (webhook direct commit, or
 * reconciliation cron heal — both call `commitPaidCartCheckoutFromStripeSession`, so both share this).
 * @param {object} pend - pendingCartCheckouts doc data (items, shippingAddress, totalCents)
 * @param {string[]} orderIds
 * @returns {{ subject: string, body: string }}
 */
function buildPaidOrderAlertText(pend, orderIds) {
  const items = Array.isArray(pend.items) ? pend.items : [];
  const bookCount = items.reduce((n, it) => n + (parseInt(it?.quantity, 10) || 1), 0);
  const totalCents = Number(pend.totalCents) || 0;
  const totalStr = (totalCents / 100).toFixed(2);
  const productSummary = items
    .map((it) => `${it?.printTitle || it?.productTitle || it?.bookVersionId || "book"} x${it?.quantity || 1}`)
    .join(", ");
  const addr = pend.shippingAddress || {};
  const cityState = [addr.city, addr.stateCode].filter(Boolean).join(", ");
  const subject = `New paid order — ${bookCount} book(s), $${totalStr}`;
  const body = [
    `Order ids: ${orderIds.join(", ") || "n/a"}`,
    `Products: ${productSummary || "n/a"}`,
    `Ship to: ${cityState || "n/a"}`,
    "",
    "Ops: https://memoirai-7db06.web.app/ops"
  ].join("\n");
  return { subject, body };
}

/**
 * Writes paid cart orders + paidBookCheckouts + checkoutAttempts + bookVersions for a completed session.
 * Order doc ids are deterministic (`ord_${sessionId}_L{idx}`) so concurrent webhook + reconciler commits are idempotent.
 *
 * @param {FirebaseFirestore.DocumentReference} pendRef
 * @param {import("stripe").Stripe.Checkout.Session} session
 * @param {{ isStripeTestMode?: boolean }} [opts]
 * @returns {Promise<{ ok: boolean, orderIds?: string[], reason?: string }>}
 */
async function commitPaidCartCheckoutFromStripeSession(pendRef, session, opts = {}) {
  const pendSnap = await pendRef.get();
  if (!pendSnap.exists) {
    return { ok: false, reason: "missing_pending" };
  }
  const pend = pendSnap.data() || {};
  if (pend.status === "paid") {
    return { ok: false, reason: "already_paid_pending_doc" };
  }

  const userIdFromMeta = pendRef.parent.parent.id;
  const cartOrderGroupId = pendRef.id;

  // Scope to this user's orders only — avoids a COLLECTION_GROUP index on `orders.stripeSessionId`
  // (collection-group queries fail until that index exists, which blocked webhook + reconciler heals).
  const dupSnap = await db
    .collection("users")
    .doc(userIdFromMeta)
    .collection("orders")
    .where("stripeSessionId", "==", session.id)
    .limit(8)
    .get();
  if (!dupSnap.empty) {
    await pendRef.set(
      {
        status: "paid",
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        stripeSessionId: session.id,
        reconcileNote: "aligned_pending_with_existing_orders"
      },
      { merge: true }
    );
    return { ok: false, reason: "orders_already_exist" };
  }

  const isStripeTestMode = opts.isStripeTestMode != null ? opts.isStripeTestMode : session.livemode === false;
  const paidTotal = session.amount_total;
  const expectedTotal = pend.totalCents || 0;
  if (paidTotal !== expectedTotal) {
    console.warn(`Cart amount mismatch session=${paidTotal} expected=${expectedTotal} group=${cartOrderGroupId}`);
  }

  const shippingAddress = pend.shippingAddress || {};
  const shippingLevel = pend.shippingLevel || "MAIL";

  const batch = db.batch();
  const createdOrderIds = [];
  const sessionIdSan = String(session.id || "").replace(/\//g, "_");
  for (let lineIdx = 0; lineIdx < (pend.items || []).length; lineIdx += 1) {
    const item = pend.items[lineIdx];
    const orderId = `ord_${sessionIdSan}_L${lineIdx}`;
    createdOrderIds.push(orderId);
    const qty = item.quantity || 1;
    const lineTotal = Number.isFinite(Number(item.lineTotalCents))
      ? Math.round(Number(item.lineTotalCents))
      : (item.unitCents || 0) * qty;
    const unit = qty > 0 ? Math.round(lineTotal / qty) : (item.unitCents || 0);
    batch.set(db.collection("users").doc(userIdFromMeta).collection("orders").doc(orderId), {
      orderId,
      cartOrderGroupId,
      bookVersionId: item.bookVersionId,
      userId: userIdFromMeta,
      stripeSessionId: session.id,
      stripePaymentIntentId: session.payment_intent || null,
      luluPrintJobId: null,
      status: "paid",
      luluError: null,
      isTestOrder: isStripeTestMode,
      customerEmail: session.customer_details?.email || session.customer_email || null,
      shippingAddress,
      shippingLevel,
      selectedProductOptionId: item.productOptionId || null,
      selectedPodPackageId: item.selectedPodPackageId || null,
      quantity: qty,
      unitCents: unit,
      lineTotalCents: lineTotal,
      pricing: {
        totalCents: lineTotal,
        currency: "usd"
      },
      printTitle: item.printTitle || null,
      productTitle: item.productTitle || null,
      bookDisplayName: item.bookDisplayName || null,
      userHandle: item.userHandle || null,
      coverPdfStoragePath: item.coverStoragePath,
      interiorPdfStoragePath: item.pdfStoragePath,
      coverURL: item.coverURL || null,
      pdfURL: item.pdfURL || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      luluTrackingUrl: null,
      luluStatusHistory: []
    });
  }

  batch.update(pendRef, {
    status: "paid",
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    stripeSessionId: session.id
  });

  const paidCheckoutRef = db
    .collection("users")
    .doc(userIdFromMeta)
    .collection("paidBookCheckouts")
    .doc(cartOrderGroupId);
  batch.set(paidCheckoutRef, {
    userId: userIdFromMeta,
    cartOrderGroupId,
    checkoutKind: "cart",
    stripeSessionId: session.id,
    stripePaymentIntentId: session.payment_intent || null,
    currency: session.currency || "usd",
    amountTotal: paidTotal != null ? paidTotal : null,
    isTestOrder: isStripeTestMode,
    quoteId: pend.quoteId || null,
    idempotencyKey: pend.idempotencyKey || null,
    checkoutPath: pend.checkoutPath || null,
    items: pend.items || [],
    shippingAddress,
    shippingLevel,
    booksSubtotalCents: pend.booksSubtotalCents != null ? pend.booksSubtotalCents : null,
    orderShippingCents: pend.orderShippingCents != null ? pend.orderShippingCents : null,
    totalCents: pend.totalCents != null ? pend.totalCents : null,
    customerEmail: session.customer_details?.email || session.customer_email || null,
    orderIds: createdOrderIds,
    paidAt: admin.firestore.FieldValue.serverTimestamp()
  });

  const rawGroup = String(cartOrderGroupId || "").trim();
  const attemptMergeId =
    (pend.checkoutAttemptDocId && String(pend.checkoutAttemptDocId).trim()) ||
    (/^book\d+$/.test(rawGroup) ? rawGroup : null) ||
    (pend.idempotencyKey && String(pend.idempotencyKey).trim()) ||
    null;
  if (attemptMergeId) {
    const attemptRef = db.collection("users").doc(userIdFromMeta).collection("checkoutAttempts").doc(attemptMergeId);
    batch.set(
      attemptRef,
      {
        paymentStatus: "paid",
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        stripePaymentIntentId: session.payment_intent || null,
        orderIds: createdOrderIds
      },
      { merge: true }
    );
  }

  const paidAtBookVersions = admin.firestore.FieldValue.serverTimestamp();
  for (let lineIdx = 0; lineIdx < (pend.items || []).length; lineIdx += 1) {
    const item = pend.items[lineIdx];
    const bid = item && item.bookVersionId ? String(item.bookVersionId).trim() : "";
    if (!bid) continue;
    const bvMerge = {
      hasPaidOrder: true,
      paidAt: paidAtBookVersions,
      lastPaidStripeSessionId: session.id
    };
    if (item.pdfStoragePath) {
      bvMerge.pdfStoragePath = item.pdfStoragePath;
    }
    if (item.coverStoragePath) {
      bvMerge.coverStoragePath = item.coverStoragePath;
    }
    if (item.pdfURL) {
      bvMerge.pdfURL = item.pdfURL;
    }
    if (item.coverURL) {
      bvMerge.coverURL = item.coverURL;
    }
    batch.set(
      db.collection("users").doc(userIdFromMeta).collection("bookVersions").doc(bid),
      bvMerge,
      { merge: true }
    );
  }

  await batch.commit();
  return { ok: true, orderIds: createdOrderIds };
}

/**
 * Flags order doc(s) for a Stripe `charge.refunded` / `charge.dispute.created` event.
 * Never mutates the fulfillment `status` state machine — only sets refundStatus/disputeStatus/
 * fulfillmentHold + timestamps + the event id, so ops can see it without a printed order being
 * silently mis-tracked. Idempotent per Stripe event id (checked per order doc).
 *
 * Order docs (both cart-line and single-book, see commitPaidCartCheckoutFromStripeSession and the
 * single-book webhook branch above) always store `stripePaymentIntentId` at write time, and
 * charge.refunded's Charge object / charge.dispute.created's Dispute object both expose
 * `payment_intent` directly, so no Stripe API round-trip is needed to map charge -> order.
 *
 * @param {import("stripe").Stripe.Event} event
 * @returns {Promise<{ handled: boolean, reason?: string, ordersFlagged?: number }>}
 */
async function handleStripeRefundOrDisputeWebhookEvent(event) {
  const obj = event.data.object;
  const paymentIntentId =
    typeof obj.payment_intent === "string"
      ? obj.payment_intent
      : (obj.payment_intent && obj.payment_intent.id) || null;
  if (!paymentIntentId) {
    console.warn(`stripeWebhook: ${event.type} missing payment_intent`, event.id);
    return { handled: false, reason: "missing_payment_intent" };
  }

  // Single-equality collection-group query, same proven pattern as luluWebhook's order lookup —
  // Firestore's automatic single-field indexes cover this without a manual composite index.
  const ordersSnap = await db
    .collectionGroup("orders")
    .where("stripePaymentIntentId", "==", paymentIntentId)
    .limit(50)
    .get();
  if (ordersSnap.empty) {
    console.warn(`stripeWebhook: ${event.type} no orders found for payment_intent ${paymentIntentId}`, event.id);
    return { handled: false, reason: "no_matching_orders" };
  }

  const isRefund = event.type === "charge.refunded";
  let flagUpdates;
  if (isRefund) {
    const amountRefunded = Number(obj.amount_refunded || 0);
    const amountCaptured = Number(obj.amount_captured != null ? obj.amount_captured : obj.amount || 0);
    const isFullRefund = obj.refunded === true || (amountCaptured > 0 && amountRefunded >= amountCaptured);
    flagUpdates = {
      refundStatus: isFullRefund ? "refunded" : "partially_refunded",
      refundedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastRefundEventId: event.id,
      lastRefundAmountCents: amountRefunded
    };
  } else {
    flagUpdates = {
      disputeStatus: "disputed",
      disputedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastDisputeEventId: event.id
    };
  }

  const batch = db.batch();
  let updated = 0;
  const flaggedOrderIds = [];
  for (const doc of ordersSnap.docs) {
    const data = doc.data() || {};
    const alreadyProcessed = isRefund
      ? data.lastRefundEventId === event.id
      : data.lastDisputeEventId === event.id;
    if (alreadyProcessed) {
      continue;
    }
    const updates = { ...flagUpdates, updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    if (!data.luluPrintJobId) {
      // Not yet submitted to Lulu — block ops from printing a refunded/disputed order.
      updates.fulfillmentHold = true;
    }
    batch.update(doc.ref, updates);
    updated += 1;
    flaggedOrderIds.push(data.orderId || doc.id);
  }
  if (updated > 0) {
    await batch.commit();
    const kind = isRefund ? "Refund" : "Dispute";
    sendOpsAlert(
      `Refund/dispute — ${flaggedOrderIds.join(", ")}`,
      `${kind} event ${event.id} for payment_intent ${paymentIntentId}.\n` +
        `Order(s) flagged: ${flaggedOrderIds.join(", ")}\n\n` +
        "Ops: https://memoirai-7db06.web.app/ops"
    ).catch(() => {});
  }
  console.log(
    `stripeWebhook: ${event.type} flagged ${updated}/${ordersSnap.size} order(s) for payment_intent ${paymentIntentId}`,
    event.id
  );
  return { handled: true, ordersFlagged: updated };
}

exports.stripeWebhook = onRequest(
  {
    timeoutSeconds: 60,
    consumeRawBody: true,
    secrets: [stripeSecretKey, stripeWebhookSecret, luluClientKey, luluClientSecret, opsAlertSmtpUrl]
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return jsonError(res, 405, "Method not allowed");
    }

    const sig = req.headers["stripe-signature"] || "";
    const rawBody = req.rawBody;
    if (!rawBody) {
      console.error("Stripe webhook: rawBody not available. Set consumeRawBody: true.");
      return jsonError(res, 500, "Server misconfiguration");
    }
    let event;
    try {
      event = Stripe.webhooks.constructEvent(
        rawBody,
        sig,
        getStripeWebhookSecret()
      );
    } catch (err) {
      console.error("Stripe webhook signature verification failed:", err.message);
      return jsonError(res, 400, "Invalid signature");
    }

    if (event.type === "charge.refunded" || event.type === "charge.dispute.created") {
      try {
        const result = await handleStripeRefundOrDisputeWebhookEvent(event);
        return res.status(200).json({ received: true, ...result });
      } catch (err) {
        // Idempotent via lastRefundEventId/lastDisputeEventId, so it's safe to let Stripe retry on 5xx.
        console.error("stripeWebhook: refund/dispute handling error", event.type, event.id, err?.message || err);
        return jsonError(res, 500, "Refund/dispute handling failed");
      }
    }

    if (event.type !== "checkout.session.completed") {
      return res.status(200).json({ received: true });
    }

    const session = event.data.object;
    const meta = session.metadata || {};
    const cartOrderGroupId = meta.cartOrderGroupId;
    const userIdFromMeta = meta.userId;

    if (cartOrderGroupId && userIdFromMeta) {
      const pendRef = db.collection("users").doc(userIdFromMeta).collection("pendingCartCheckouts").doc(cartOrderGroupId);
      const pendSnap = await pendRef.get();
      if (!pendSnap.exists) {
        console.error("Stripe webhook: pending cart missing", cartOrderGroupId);
        return jsonError(res, 400, "Missing pending checkout");
      }
      const pend = pendSnap.data();
      if (pend.status === "paid") {
        console.log(`Duplicate cart webhook for ${cartOrderGroupId}, skipping`);
        return res.status(200).json({ received: true, duplicate: true, cart: true });
      }

      const commitResult = await commitPaidCartCheckoutFromStripeSession(pendRef, session, {
        isStripeTestMode: event.livemode === false
      });
      if (!commitResult.ok) {
        if (commitResult.reason === "already_paid_pending_doc") {
          console.log(`Duplicate cart webhook for ${cartOrderGroupId}, skipping`);
          return res.status(200).json({ received: true, duplicate: true, cart: true });
        }
        if (commitResult.reason === "orders_already_exist") {
          return res.status(200).json({ received: true, duplicate: true, cart: true, healed: true });
        }
        if (commitResult.reason === "missing_pending") {
          console.error("Stripe webhook: pending cart missing", cartOrderGroupId);
          return jsonError(res, 400, "Missing pending checkout");
        }
        return jsonError(res, 500, "Cart checkout commit failed");
      }

      {
        const { subject, body } = buildPaidOrderAlertText(pend, commitResult.orderIds);
        sendOpsAlert(subject, body).catch(() => {});
      }

      console.log(`Cart paid: orders=${commitResult.orderIds.length} group=${cartOrderGroupId}`);
      return res.status(200).json({ received: true, cart: true, orderIds: commitResult.orderIds });
    }

    const {
      bookVersionId,
      userId,
      shippingAddress: addrJson,
      shippingLevel,
      coverStoragePath,
      pdfStoragePath,
      selectedProductOptionId,
      selectedPodPackageId
    } = meta;
    if (!bookVersionId || !userId || !addrJson || !coverStoragePath || !pdfStoragePath) {
      console.error("Stripe webhook: missing metadata", session.metadata);
      return jsonError(res, 400, "Missing metadata");
    }

    let shippingAddress;
    try {
      shippingAddress = JSON.parse(addrJson);
    } catch (e) {
      return jsonError(res, 400, "Invalid shipping address");
    }

    const existingSnap = await db
      .collection("users")
      .doc(userId)
      .collection("orders")
      .where("stripeSessionId", "==", session.id)
      .limit(1)
      .get();
    if (!existingSnap.empty) {
      console.log(`Duplicate webhook for session ${session.id}, skipping`);
      return res.status(200).json({ received: true, duplicate: true });
    }

    const orderId = `ord_${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;

    const isStripeTestMode = event.livemode === false;
    const lineTotalCentsSingle = parseInt(session.metadata?.totalCents || "2999", 10);

    let profileIdSingle = null;
    let printTitleSingle = null;
    let bvUrls = {};
    try {
      await ensureBookVersionArtifactUrls(db, bucket, userId, bookVersionId);
      const bvSnap = await db.collection("users").doc(userId).collection("bookVersions").doc(bookVersionId).get();
      if (bvSnap.exists) {
        const rec = bvSnap.data() || {};
        bvUrls = rec;
        profileIdSingle = rec.profileId != null ? String(rec.profileId) : null;
        printTitleSingle = printTitleFromBookVersionRecord(rec);
      }
    } catch (e) {
      console.warn("Stripe webhook single-book: bookVersions fetch failed", e.message || e);
    }

    const orderData = {
      orderId,
      bookVersionId,
      userId,
      stripeSessionId: session.id,
      stripePaymentIntentId: session.payment_intent || null,
      luluPrintJobId: null,
      status: "paid",
      luluError: null,
      isTestOrder: isStripeTestMode,
      customerEmail: session.customer_details?.email || session.customer_email || null,
      shippingAddress,
      shippingLevel: shippingLevel || "MAIL",
      selectedProductOptionId: selectedProductOptionId || null,
      selectedPodPackageId: selectedPodPackageId || null,
      quantity: 1,
      unitCents: lineTotalCentsSingle,
      lineTotalCents: lineTotalCentsSingle,
      pricing: {
        totalCents: lineTotalCentsSingle,
        currency: "usd"
      },
      printTitle: printTitleSingle,
      productTitle: null,
      bookDisplayName: bvUrls.bookDisplayName || null,
      userHandle: bvUrls.userHandle || null,
      coverPdfStoragePath: coverStoragePath,
      interiorPdfStoragePath: pdfStoragePath,
      coverURL: bvUrls.coverURL || null,
      pdfURL: bvUrls.pdfURL || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      luluTrackingUrl: null,
      luluStatusHistory: []
    };

    const orderRef = db.collection("users").doc(userId).collection("orders").doc(orderId);
    const paidSingleRef = db.collection("users").doc(userId).collection("paidBookCheckouts").doc(orderId);
    const batchSingle = db.batch();
    batchSingle.set(orderRef, orderData);
    batchSingle.set(paidSingleRef, {
      userId,
      checkoutKind: "single_book",
      cartOrderGroupId: null,
      stripeSessionId: session.id,
      stripePaymentIntentId: session.payment_intent || null,
      currency: session.currency || "usd",
      amountTotal: session.amount_total != null ? session.amount_total : lineTotalCentsSingle,
      isTestOrder: isStripeTestMode,
      quoteId: null,
      idempotencyKey: null,
      checkoutPath: "single_book",
      items: [
        {
          bookVersionId,
          profileId: profileIdSingle,
          printTitle: printTitleSingle,
          productOptionId: selectedProductOptionId || null,
          selectedPodPackageId: selectedPodPackageId || null,
          quantity: 1,
          unitCents: lineTotalCentsSingle,
          lineTotalCents: lineTotalCentsSingle,
          coverStoragePath,
          pdfStoragePath,
          coverURL: bvUrls.coverURL || null,
          pdfURL: bvUrls.pdfURL || null,
          bookDisplayName: bvUrls.bookDisplayName || null,
          userHandle: bvUrls.userHandle || null
        }
      ],
      shippingAddress,
      shippingLevel: shippingLevel || "MAIL",
      booksSubtotalCents: lineTotalCentsSingle,
      orderShippingCents: 0,
      totalCents: lineTotalCentsSingle,
      customerEmail: session.customer_details?.email || session.customer_email || null,
      orderIds: [orderId],
      paidAt: admin.firestore.FieldValue.serverTimestamp()
    });
    batchSingle.set(
      db.collection("users").doc(userId).collection("bookVersions").doc(bookVersionId),
      {
        hasPaidOrder: true,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPaidStripeSessionId: session.id,
        pdfStoragePath,
        coverStoragePath,
        pdfURL: bvUrls.pdfURL || null,
        coverURL: bvUrls.coverURL || null
      },
      { merge: true }
    );
    await batchSingle.commit();

    console.log(`Order ${orderId} saved as 'paid'. Awaiting manual fulfillment.`);
    return res.status(200).json({ received: true, orderId, status: "paid" });
  }
);

// ── Admin: manually submit a paid order to Lulu for printing ──
exports.fulfillOrder = onCall(
  {
    timeoutSeconds: 120,
    secrets: [luluClientKey, luluClientSecret, opsAlertSmtpUrl]
  },
  async (request) => {
    assertMemoirAdmin(request);
    const { orderId, userId: targetUserId } = request.data || {};
    if (!orderId || !targetUserId) {
      throw new HttpsError("invalid-argument", "orderId and userId are required");
    }

    const orderRef = db.collection("users").doc(targetUserId).collection("orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Order not found");
    }
    const order = orderSnap.data();
    const st = order.status;
    const retriable = st === "paid" || st === "lulu_failed" ||
      (st === "pending_fulfillment" && !order.luluPrintJobId);
    if (!retriable) {
      throw new HttpsError(
        "failed-precondition",
        `Order status is '${st}', expected paid, lulu_failed, or pending_fulfillment without a Lulu job`
      );
    }
    if (order.isTestOrder) {
      throw new HttpsError("failed-precondition", "Cannot fulfill a test order");
    }
    if (order.fulfillmentHold) {
      throw new HttpsError(
        "failed-precondition",
        "Order is on hold due to a refund or dispute. Resolve before printing."
      );
    }

    let result;
    try {
      result = await submitPaidOrderToLulu({
        orderRef,
        orderData: order,
        orderId,
        userId: targetUserId,
        source: "manual_fulfill"
      });
    } catch (err) {
      throw new HttpsError("internal", String(err?.message || err || "Failed to submit to Lulu"));
    }

    return { success: true, orderId, luluJobId: result.luluJobId || null, status: result.mappedStatus || "submitted_to_printer" };
  }
);

// Auto-submit newly paid orders to Lulu so Lulu dashboard and Firestore stay aligned.
exports.autoFulfillPaidOrder = onDocumentCreated(
  {
    document: "users/{userId}/orders/{orderId}",
    timeoutSeconds: 120,
    secrets: [luluClientKey, luluClientSecret, opsAlertSmtpUrl]
  },
  async (event) => {
    const data = event.data?.data();
    const orderRef = event.data?.ref;
    const userId = event.params?.userId;
    const orderId = event.params?.orderId;
    if (!data || !orderRef || !userId || !orderId) {
      return;
    }
    if (data.status !== "paid" || data.isTestOrder || data.luluPrintJobId || data.fulfillmentHold) {
      return;
    }
    if (!isAutoFulfillPaidOrdersEnabled()) {
      console.log(
        `autoFulfillPaidOrder skipped order=${orderId} (AUTO_FULFILL_PAID_ORDERS is not true; use ops Print queue)`
      );
      return;
    }
    try {
      await submitPaidOrderToLulu({
        orderRef,
        orderData: data,
        orderId,
        userId,
        source: "auto_fulfill_trigger"
      });
    } catch (err) {
      console.error(`autoFulfillPaidOrder failed order=${orderId} user=${userId}:`, err?.message || err);
    }
  }
);

exports.syncOrderFromLulu = onCall(
  {
    timeoutSeconds: 60,
    secrets: [luluClientKey, luluClientSecret]
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const { orderId, userId: targetUserId } = request.data || {};
    if (!orderId || !targetUserId) {
      throw new HttpsError("invalid-argument", "orderId and userId are required");
    }
    if (request.auth.uid !== targetUserId) {
      throw new HttpsError("permission-denied", "Can only sync your own orders");
    }
    const orderRef = db.collection("users").doc(targetUserId).collection("orders").doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Order not found");
    }
    const orderData = snap.data() || {};
    try {
      const result = await syncOrderStatusFromLulu({ orderRef, orderData });
      return { ok: true, ...result };
    } catch (err) {
      throw new HttpsError("internal", String(err?.message || err || "Lulu sync failed"));
    }
  }
);

function verifyLuluWebhookSignature(rawBody, signature, clientSecret) {
  if (!rawBody || !signature || !clientSecret) return false;
  try {
    const payload = typeof rawBody === "string" ? Buffer.from(rawBody, "utf8") : rawBody;
    const expected = crypto.createHmac("sha256", clientSecret).update(payload).digest("hex");
    const sigBuf = Buffer.from(signature.trim(), "hex");
    const expBuf = Buffer.from(expected, "hex");
    return sigBuf.length === expBuf.length && crypto.timingSafeEqual(sigBuf, expBuf);
  } catch {
    return false;
  }
}

exports.luluWebhook = onRequest(
  {
    timeoutSeconds: 30,
    consumeRawBody: true,
    secrets: [luluClientSecret]
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return jsonError(res, 405, "Method not allowed");
    }

    const signature = req.headers["lulu-hmac-sha256"] || req.headers["Lulu-HMAC-SHA256"];
    const rawBody = req.rawBody;
    const clientSecret = luluClientSecret.value();
    if (!verifyLuluWebhookSignature(rawBody, signature, clientSecret)) {
      console.warn("Lulu webhook: HMAC signature verification failed");
      return jsonError(res, 401, "Invalid signature");
    }

    const payload = req.body || {};
    const eventType = payload.event_type || payload.eventType;
    if (eventType !== "PRINT_JOB_STATUS_CHANGED") {
      return res.status(200).json({ received: true });
    }

    const jobId = payload.print_job_id || payload.printJobId || payload.id;
    const status = payload.status || payload.state;
    const externalId = payload.external_id || payload.externalId;
    const trackingUrl = payload.tracking_url || payload.trackingUrl;

    if (!jobId && !externalId) {
      return jsonError(res, 400, "Missing print job identifier");
    }

    let orderQuery = db.collectionGroup("orders");
    if (externalId) {
      orderQuery = orderQuery.where("orderId", "==", externalId);
    } else {
      orderQuery = orderQuery.where("luluPrintJobId", "==", String(jobId));
    }
    const snap = await orderQuery.limit(1).get();
    if (snap.empty) {
      console.warn("Lulu webhook: order not found for job", jobId, externalId);
      return res.status(200).json({ received: true });
    }

    const orderDoc = snap.docs[0];
    const orderRef = orderDoc.ref;
    const orderData = orderDoc.data() || {};
    const hist = pushStatusHistory(orderData.luluStatusHistory, {
      status,
      trackingUrl: trackingUrl || null,
      source: "lulu_webhook"
    });
    const ourStatus = mapLuluStatusToOrderStatus(status);

    const updates = {
      status: ourStatus,
      luluRawStatus: status || null,
      luluLastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      luluStatusHistory: hist
    };
    if (trackingUrl) {
      updates.luluTrackingUrl = trackingUrl;
    }

    await orderRef.update(updates);
    return res.status(200).json({ received: true });
  }
);

/** Scheduled: reconcile stale Stripe Checkout sessions on pending cart checkouts. */
exports.reconcilePendingCartCheckouts = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Etc/UTC",
    secrets: [stripeSecretKey, opsAlertSmtpUrl],
    timeoutSeconds: 300,
    memory: "256MiB"
  },
  async () => {
    const runStartMs = Date.now();
    const debugId = `rcc_${Date.now()}_${crypto.randomBytes(3).toString("hex")}`;
    const stripe = createStripeClient({ maxNetworkRetries: 3, timeoutMs: 25 * 1000 });
    const threshold = admin.firestore.Timestamp.fromMillis(Date.now() - 45 * 60 * 1000);
    let snap;
    try {
      snap = await db
        .collectionGroup("pendingCartCheckouts")
        .where("status", "==", "pending_stripe")
        .where("createdAt", "<", threshold)
        .limit(40)
        .get();
    } catch (err) {
      console.error("reconcilePendingCartCheckouts query failed:", err.message || err);
      return;
    }
    if (snap.empty) {
      return;
    }
    let processed = 0;
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      if (data.status === "paid") {
        continue;
      }
      const sid = data.stripeSessionId;
      if (!sid) {
        continue;
      }
      try {
        const session = await stripe.checkout.sessions.retrieve(String(sid));
        const updates = {
          checkoutReconcileAt: admin.firestore.FieldValue.serverTimestamp(),
          stripeSessionStatus: session.status || null,
          stripePaymentStatus: session.payment_status || null
        };
        if (session.status === "expired") {
          updates.status = "checkout_expired";
          updates.reconcileNote = "stripe_session_expired";
        } else if (session.status === "complete" && session.payment_status === "paid" && data.status !== "paid") {
          try {
            const heal = await commitPaidCartCheckoutFromStripeSession(doc.ref, session, {
              isStripeTestMode: session.livemode === false
            });
            if (heal.ok) {
              updates.reconcileNote = "healed_by_reconcilePendingCartCheckouts";
              const { subject, body } = buildPaidOrderAlertText(data, heal.orderIds || []);
              sendOpsAlert(subject, body).catch(() => {});
              console.warn(
                JSON.stringify({
                  msg: "reconcilePendingCartCheckouts:healed_paid_pending",
                  path: doc.ref.path,
                  cartOrderGroupId: data.cartOrderGroupId || null,
                  stripeSessionId: sid,
                  orderIds: heal.orderIds || []
                })
              );
            } else if (heal.reason === "already_paid_pending_doc" || heal.reason === "orders_already_exist") {
              updates.reconcileNote = heal.reason;
            } else {
              console.warn(
                JSON.stringify({
                  msg: "reconcilePendingCartCheckouts:paid_but_pending_doc",
                  path: doc.ref.path,
                  cartOrderGroupId: data.cartOrderGroupId || null,
                  stripeSessionId: sid,
                  healReason: heal.reason || null
                })
              );
              updates.reconcileNote = "stripe_paid_pending_firestore_mismatch";
            }
          } catch (healErr) {
            console.warn(
              JSON.stringify({
                msg: "reconcilePendingCartCheckouts:heal_failed",
                path: doc.ref.path,
                stripeSessionId: sid,
                error: String(healErr?.message || healErr)
              })
            );
            updates.reconcileNote = "stripe_paid_heal_exception";
          }
        }
        await doc.ref.set(updates, { merge: true });
        processed += 1;
      } catch (e) {
        console.warn(
          "reconcilePendingCartCheckouts retrieve failed:",
          doc.ref.path,
          String(e?.message || e)
        );
      }
    }
    if (processed > 0 || !snap.empty) {
      console.log(
        JSON.stringify({
          msg: "reconcilePendingCartCheckouts:run_complete",
          debugId,
          stage: "complete",
          processed,
          candidateDocs: snap.size,
          elapsedMs: Date.now() - runStartMs
        })
      );
    }
  }
);

/** Admin ops: all print orders + queue subset + dashboard stats. See public/ops and OPS_PRINT_QUEUE.md. */
exports.adminListPrintOrders = onCall({ timeoutSeconds: 120 }, async (request) => {
  assertMemoirAdmin(request);
  const lim = Math.min(250, Math.max(1, parseInt(request.data?.limit, 10) || 200));
  const usersSnap = await db.collection("users").get();
  const all = [];
  for (const userDoc of usersSnap.docs) {
    const ordersSnap = await userDoc.ref.collection("orders").get();
    for (const orderDoc of ordersSnap.docs) {
      const data = orderDoc.data() || {};
      if (data.isTestOrder) continue;
      all.push(orderRecordForOpsQueue(orderDoc.id, userDoc.id, data));
    }
  }
  const sortByCreated = (a, b) => {
    const ta = a.createdAt || "";
    const tb = b.createdAt || "";
    return tb.localeCompare(ta);
  };
  all.sort(sortByCreated);
  const pending = all.filter((o) => o.needsPrintAction);
  let totalRevenueCents = 0;
  let totalProfitCents = 0;
  const statusCounts = {};
  for (const o of all) {
    const st = o.status || "unknown";
    statusCounts[st] = (statusCounts[st] || 0) + 1;
    if (typeof o.totalCents === "number") {
      totalRevenueCents += o.totalCents;
    }
    if (typeof o.totalCents === "number" && o.luluTotalCostInclTax != null) {
      const luluCents = Math.round(parseFloat(o.luluTotalCostInclTax) * 100);
      if (!isNaN(luluCents)) {
        totalProfitCents += o.totalCents - luluCents;
      }
    }
  }
  const slice = (arr) => arr.slice(0, lim);
  return {
    autoFulfillEnabled: isAutoFulfillPaidOrdersEnabled(),
    userCount: usersSnap.size,
    stats: {
      totalOrders: all.length,
      needsPrint: pending.length,
      totalRevenueCents,
      totalProfitCents,
      statusCounts
    },
    all: slice(all),
    allCount: all.length,
    pending: slice(pending),
    pendingCount: pending.length
  };
});

/** Admin: refresh order status from Lulu API (same as syncOrderFromLulu, admin-only). */
exports.adminSyncOrderFromLulu = onCall(
  {
    timeoutSeconds: 60,
    secrets: [luluClientKey, luluClientSecret]
  },
  async (request) => {
    assertMemoirAdmin(request);
    const { orderId, userId: targetUserId } = request.data || {};
    if (!orderId || !targetUserId) {
      throw new HttpsError("invalid-argument", "orderId and userId are required");
    }
    const orderRef = db.collection("users").doc(targetUserId).collection("orders").doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Order not found");
    }
    const orderData = snap.data() || {};
    if (!orderData.luluPrintJobId) {
      throw new HttpsError("failed-precondition", "Order has no luluPrintJobId yet");
    }
    try {
      const result = await syncOrderStatusFromLulu({ orderRef, orderData });
      return { ok: true, ...result };
    } catch (err) {
      throw new HttpsError("internal", String(err?.message || err || "Lulu sync failed"));
    }
  }
);

/** Admin/support: list `bookVersions` for a user (callable). Requires `ADMIN_EMAILS` or Auth claim `admin`. */
exports.adminListUserBooks = onCall({ timeoutSeconds: 60 }, async (request) => {
  assertMemoirAdmin(request);
  const targetUid = String(request.data?.userId || "").trim();
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "userId is required");
  }
  const lim = Math.min(100, Math.max(1, parseInt(request.data?.limit, 10) || 50));
  const snap = await db.collection("users").doc(targetUid).collection("bookVersions").limit(lim).get();
  const books = snap.docs.map((d) => {
    const data = d.data() || {};
    return {
      bookVersionId: d.id,
      profileId: data.profileId != null ? String(data.profileId) : null,
      printTitle: data.printTitle != null ? String(data.printTitle) : null,
      bookDisplayName: data.bookDisplayName != null ? String(data.bookDisplayName) : null,
      userHandle: data.userHandle != null ? String(data.userHandle) : null,
      bookSeq: data.bookSeq != null ? data.bookSeq : null,
      displayHandle: data.displayHandle != null ? String(data.displayHandle) : null,
      bookNumber: data.bookNumber != null ? data.bookNumber : null,
      pageCount: data.pageCount != null ? data.pageCount : null,
      renderStatus: data.renderStatus != null ? String(data.renderStatus) : null,
      hasPaidOrder: data.hasPaidOrder === true,
      paidAt: data.paidAt || null,
      pdfURL: data.pdfURL != null ? String(data.pdfURL) : null,
      coverURL: data.coverURL != null ? String(data.coverURL) : null,
      createdAt: data.createdAt || null
    };
  });
  return { books, count: books.length };
});

/** Admin: verify PDFs for an order before submitting to Lulu (callable). */
exports.adminVerifyOrderPdfs = onCall(
  {
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [luluClientKey, luluClientSecret]
  },
  async (request) => {
    assertMemoirAdmin(request);
    const { orderId, userId: targetUserId } = request.data || {};
    if (!orderId || !targetUserId) {
      throw new HttpsError("invalid-argument", "orderId and userId are required");
    }

    const orderRef = db.collection("users").doc(targetUserId).collection("orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Order not found");
    }
    const orderData = orderSnap.data() || {};

    const coverStoragePath = orderData.coverPdfStoragePath;
    const interiorStoragePath = orderData.interiorPdfStoragePath;
    if (!coverStoragePath || !interiorStoragePath) {
      throw new HttpsError(
        "failed-precondition",
        "Order is missing PDF storage paths. The book may not have been rendered yet."
      );
    }

    // Use the Firebase Storage download URLs already on the order — no signed URLs needed for preview.
    // Signed URLs are only required by Lulu (generated at submit time in fulfillOrder).
    const coverDownloadUrl = orderData.coverURL || null;
    const interiorDownloadUrl = orderData.pdfURL || null;

    // podPackageId and pageCount match the logic in submitPaidOrderToLulu
    let podPackageId = orderData.selectedPodPackageId || null;
    if (!podPackageId) {
      try {
        const inputs = await getBookVersionOrderInputs(
          targetUserId,
          orderData.bookVersionId,
          orderData.selectedProductOptionId || null
        );
        podPackageId = inputs.podPackageId || null;
      } catch (_) { /* non-fatal — will surface as missing below */ }
    }

    // pageCount lives on the bookVersion doc, not the order
    let pageCount = null;
    if (orderData.bookVersionId) {
      try {
        const bvSnap = await db.collection("users").doc(targetUserId)
          .collection("bookVersions").doc(orderData.bookVersionId).get();
        const bv = bvSnap.exists ? bvSnap.data() : {};
        pageCount = bv.pageCount || bv.pages?.length || null;
      } catch (_) { /* non-fatal */ }
    }

    // Check file existence and sizes from GCS metadata (direct bucket access, no signing)
    const [coverExistsArr, interiorExistsArr] = await Promise.all([
      bucket.file(coverStoragePath).exists(),
      bucket.file(interiorStoragePath).exists()
    ]);
    const coverExists = coverExistsArr[0];
    const interiorExists = interiorExistsArr[0];

    let interiorFileSizeBytes = null;
    let coverFileSizeBytes = null;
    try {
      const metaResults = await Promise.all([
        interiorExists ? bucket.file(interiorStoragePath).getMetadata() : Promise.resolve([null]),
        coverExists ? bucket.file(coverStoragePath).getMetadata() : Promise.resolve([null])
      ]);
      interiorFileSizeBytes = metaResults[0][0]?.size ? parseInt(metaResults[0][0].size, 10) : null;
      coverFileSizeBytes = metaResults[1][0]?.size ? parseInt(metaResults[1][0].size, 10) : null;
    } catch (_) { /* non-fatal */ }

    // Interior page count comes from the bookVersion doc — no need to download the 40MB interior PDF
    const interiorPageCount = pageCount;

    // Fetch Lulu auth once, then run dimension check + cost estimate in parallel
    let coverDimensionCheck = null;
    let luluCostEstimate = null;

    if (!podPackageId || !pageCount) {
      coverDimensionCheck = {
        pass: false,
        error: "Order is missing podPackageId or pageCount — cannot check cover dimensions"
      };
    } else if (!coverExists) {
      coverDimensionCheck = { pass: false, error: "Cover PDF does not exist in storage" };
    } else {
      try {
        // Download cover PDF once and run Lulu API calls in parallel
        const [luluAuth, [coverBuf]] = await Promise.all([
          getLuluAccessToken(),
          bucket.file(coverStoragePath).download()
        ]);

        const [dims, costResult] = await Promise.all([
          luluPostCoverDimensions(luluAuth.accessToken, luluAuth.luluBaseUrl, podPackageId, pageCount),
          luluCalculateCost(
            luluAuth.accessToken,
            luluAuth.luluBaseUrl,
            podPackageId,
            pageCount,
            orderData.shippingAddress || {},
            orderData.shippingLevel || "MAIL",
            Math.min(99, Math.max(1, parseInt(orderData.quantity, 10) || 1))
          ).catch((e) => ({ _error: String(e?.message || e) }))
        ]);

        // Cover dimension check
        const expW = parseFloat(dims.width);
        const expH = parseFloat(dims.height);
        const coverPdf = await PDFDocument.load(coverBuf);
        const page0 = coverPdf.getPage(0);
        const { width: wPt, height: hPt } = page0.getSize();
        const wIn = wPt / 72;
        const hIn = hPt / 72;
        const tol = 0.0625;
        const pass = Math.abs(wIn - expW) <= tol && Math.abs(hIn - expH) <= tol;
        coverDimensionCheck = {
          expectedWidth: +expW.toFixed(4),
          expectedHeight: +expH.toFixed(4),
          actualWidth: +wIn.toFixed(4),
          actualHeight: +hIn.toFixed(4),
          toleranceIn: tol,
          pass,
          luluEnvironment: luluAuth.environment
        };

        // Cost estimate — use existing extraction helpers since shipping_cost/line_item_cost are nested objects
        if (costResult._error) {
          luluCostEstimate = { error: costResult._error };
        } else {
          const shippingCents = extractLuluShippingCents(costResult);
          const lineItemCents = extractLuluLineItemMakeCents(costResult);
          luluCostEstimate = {
            totalCostInclTax: costResult.total_cost_incl_tax || null,
            shippingCostDollars: shippingCents > 0 ? (shippingCents / 100).toFixed(2) : null,
            lineItemCostDollars: lineItemCents > 0 ? (lineItemCents / 100).toFixed(2) : null,
            currency: costResult.currency || "USD",
            luluEnvironment: luluAuth.environment
          };
        }
      } catch (err) {
        coverDimensionCheck = { pass: false, error: String(err?.message || err) };
      }
    }

    // Customer paid to MemoirAI — totalCents lives at pricing.totalCents or root lineTotalCents
    const pricing = (orderData.pricing && typeof orderData.pricing === "object") ? orderData.pricing : {};
    const customerPaidCents = (pricing.totalCents != null) ? pricing.totalCents
      : (orderData.lineTotalCents != null) ? orderData.lineTotalCents
      : (orderData.totalCents != null) ? orderData.totalCents
      : null;
    const customerCurrency = pricing.currency || orderData.currency || "usd";

    return {
      coverExists,
      interiorExists,
      coverDownloadUrl,
      interiorDownloadUrl,
      coverFileSizeBytes,
      interiorFileSizeBytes,
      podPackageId,
      pageCount,
      interiorPageCount,
      coverDimensionCheck,
      luluCostEstimate,
      customerPaidCents,
      customerCurrency,
      orderStatus: orderData.status
    };
  }
);

// ── User / book / memory display naming + purchasedBooks mirror (Firestore v2) ──
exports.onUserDocumentBootstrapHandle = onDocumentCreated(
  { document: "users/{userId}" },
  async (event) => {
    const uid = event.params.userId;
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    if (data.userHandle) return;
    try {
      await naming.ensureUserHandleAllocated(db, uid);
    } catch (e) {
      console.error("onUserDocumentBootstrapHandle failed", uid, String(e?.message || e));
    }
  }
);

exports.onBookVersionDisplayNaming = onDocumentCreated(
  { document: "users/{userId}/bookVersions/{bookVersionId}" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    if (data.bookDisplayName) return;
    const userId = event.params.userId;
    try {
      const handle = await naming.resolveUserHandleForNaming(db, userId);
      const seq = await naming.allocateGlobalCounter(db, "globalBooks");
      const bookDisplayName = naming.bookDisplayNameFor(handle, seq);
      await snap.ref.set(
        {
          bookDisplayName,
          bookSeq: seq,
          userHandle: handle
        },
        { merge: true }
      );
    } catch (e) {
      console.error("onBookVersionDisplayNaming failed", userId, String(e?.message || e));
    }
  }
);

exports.onMemoryDisplayNaming = onDocumentCreated(
  { document: "users/{userId}/memories/{memoryId}" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    const userId = event.params.userId;
    const memoryId = event.params.memoryId;
    // memoryIndex powers QR scans from other people's phones: memoryId -> ownerId.
    // Kept here (not a second trigger) to save an invocation per memory.
    try {
      await db.collection("memoryIndex").doc(memoryId).set(
        {
          ownerId: userId,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        },
        { merge: true }
      );
    } catch (e) {
      console.error("memoryIndex upsert failed", userId, memoryId, String(e?.message || e));
    }
    if (data.memoryDisplayName) return;
    try {
      const handle = await naming.resolveUserHandleForNaming(db, userId);
      const seq = await naming.allocateGlobalCounter(db, "globalMemories");
      const memoryDisplayName = naming.memoryDisplayNameFor(handle, seq);
      await snap.ref.set(
        {
          memoryDisplayName,
          memorySeq: seq,
          userHandle: handle
        },
        { merge: true }
      );
    } catch (e) {
      console.error("onMemoryDisplayNaming failed", userId, String(e?.message || e));
    }
  }
);

exports.onMemoryIndexCleanup = onDocumentDeleted(
  { document: "users/{userId}/memories/{memoryId}" },
  async (event) => {
    try {
      await db.collection("memoryIndex").doc(event.params.memoryId).delete();
    } catch (e) {
      console.error("memoryIndex cleanup failed", event.params.memoryId, String(e?.message || e));
    }
  }
);

exports.onOrderMirrorPurchasedBooks = onDocumentWritten(
  { document: "users/{userId}/orders/{orderId}" },
  createOrderMirrorHandler(db, bucket)
);

// Storybook cloud AI generation (Firestore-triggered; secrets OPENAI_API_KEY + GEMINI_API_KEY)
Object.assign(exports, require("./storybookWorker"));

// Server-side AI proxy callables (onCall; secrets OPENAI_API_KEY + GEMINI_API_KEY) — client never holds provider keys.
Object.assign(exports, require("./aiProxy"));
