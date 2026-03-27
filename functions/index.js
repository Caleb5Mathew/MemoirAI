const admin = require("firebase-admin");
const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { PDFDocument } = require("pdf-lib");
const crypto = require("crypto");
const Stripe = require("stripe");

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

const LULU_SANDBOX = process.env.LULU_USE_SANDBOX === "true";
const LULU_BASE = LULU_SANDBOX
  ? "https://api.sandbox.lulu.com"
  : "https://api.lulu.com";
const LULU_AUTH_URL = LULU_SANDBOX
  ? "https://api.sandbox.lulu.com/auth/realms/glasstree/protocol/openid-connect/token"
  : "https://api.lulu.com/auth/realms/glasstree/protocol/openid-connect/token";

function jsonError(res, code, message) {
  res.status(code).json({ status: "failed", message });
}

async function verifyUser(req) {
  const authHeader = req.headers.authorization || "";
  if (!authHeader.startsWith("Bearer ")) {
    throw new Error("Missing bearer token");
  }
  const token = authHeader.replace("Bearer ", "").trim();
  return admin.auth().verifyIdToken(token);
}

async function getLuluAccessToken() {
  const clientKey = luluClientKey.value();
  const clientSecret = luluClientSecret.value();
  if (!clientKey || !clientSecret) {
    throw new Error("LULU_CLIENT_KEY and LULU_CLIENT_SECRET must be set");
  }
  const encoded = Buffer.from(`${clientKey}:${clientSecret}`).toString("base64");
  const res = await fetch(LULU_AUTH_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Authorization": `Basic ${encoded}`
    },
    body: "grant_type=client_credentials"
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Lulu auth failed: ${res.status} ${text}`);
  }
  const data = await res.json();
  return data.access_token;
}

async function luluCalculateCost(accessToken, podPackageId, pageCount, shippingAddress, shippingLevel) {
  const res = await fetch(`${LULU_BASE}/print-job-cost-calculations/`, {
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
          quantity: 1
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
    throw new Error(`Lulu cost calculation failed: ${res.status} ${text}`);
  }
  return res.json();
}

async function luluCreatePrintJob(accessToken, payload) {
  const res = await fetch(`${LULU_BASE}/print-jobs/`, {
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

async function getSignedUrl(storagePath, expiresInSeconds = 604800) {
  const file = bucket.file(storagePath);
  const [url] = await file.getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + expiresInSeconds * 1000
  });
  return url;
}

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
  if (!forceRegenerate && record.renderStatus === "rendered" && record.pdfURL) {
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

exports.createCheckoutSession = onCall(
  {
    timeoutSeconds: 60,
    secrets: [stripeSecretKey, luluClientKey, luluClientSecret]
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in to order a book");
    }
    const userId = request.auth.uid;
    const { bookVersionId, shippingAddress, shippingLevel = "MAIL" } = request.data || {};
    if (!bookVersionId || !shippingAddress) {
      throw new HttpsError("invalid-argument", "bookVersionId and shippingAddress are required");
    }

    const docRef = db.collection("users").doc(userId).collection("bookVersions").doc(bookVersionId);
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Book not found");
    }
    const record = snapshot.data() || {};
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
    const podPackageId = pricing?.luluPodPackageId
      ?? (isLandscape ? "1100X0850FCSTDCW080CW444MXX" : "0850X1100FCSTDCW080CW444MXX");
    const baseCents = pricing?.basePriceCents ?? 2999;
    const marginPercent = pricing?.marginPercent ?? 30;
    const dimensions = isLandscape ? "11x8.5\"" : "8.5x11\"";

    let totalCents = baseCents;
    try {
      const accessToken = await getLuluAccessToken();
      const costResult = await luluCalculateCost(
        accessToken,
        podPackageId,
        pageCount,
        {
          street1: shippingAddress.street1,
          city: shippingAddress.city,
          stateCode: shippingAddress.stateCode || "",
          countryCode: shippingAddress.countryCode || "US",
          postcode: shippingAddress.postcode,
          phone: shippingAddress.phone
        },
        shippingLevel
      );
      const luluTotalDollars = parseFloat(costResult.total_cost_incl_tax || "0");
      const luluTotalCents = Math.round(luluTotalDollars * 100);
      if (luluTotalCents > 0) {
        totalCents = Math.max(baseCents, Math.round(luluTotalCents * (1 + (marginPercent / 100))));
      } else {
        totalCents = baseCents;
      }
    } catch (err) {
      console.warn("Lulu cost calculation failed, using base price:", err.message);
      totalCents = baseCents;
    }

    const stripe = new Stripe(stripeSecretKey.value());
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [
        {
          price_data: {
            currency: "usd",
            product_data: {
              name: "MemoirAI Printed Book",
              description: `${dimensions} Hardcover, Full Color, Matte. ${pageCount} pages.`,
              images: []
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
        pdfStoragePath
      },
      customer_email: request.auth.token?.email || undefined,
      payment_intent_data: {
        receipt_email: request.auth.token?.email || undefined
      }
    });

    return { checkoutUrl: session.url, sessionId: session.id };
  }
);

exports.stripeWebhook = onRequest(
  {
    timeoutSeconds: 60,
    consumeRawBody: true,
    secrets: [stripeSecretKey, stripeWebhookSecret, luluClientKey, luluClientSecret]
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
        stripeWebhookSecret.value()
      );
    } catch (err) {
      console.error("Stripe webhook signature verification failed:", err.message);
      return jsonError(res, 400, "Invalid signature");
    }

    if (event.type !== "checkout.session.completed") {
      return res.status(200).json({ received: true });
    }

    const session = event.data.object;
    const { bookVersionId, userId, shippingAddress: addrJson, shippingLevel, coverStoragePath, pdfStoragePath } = session.metadata || {};
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

    // Idempotency: check for existing order with same Stripe session
    const existingSnap = await db.collectionGroup("orders")
      .where("stripeSessionId", "==", session.id)
      .limit(1)
      .get();
    if (!existingSnap.empty) {
      console.log(`Duplicate webhook for session ${session.id}, skipping`);
      return res.status(200).json({ received: true, duplicate: true });
    }

    const orderId = `ord_${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;

    const isStripeTestMode = event.livemode === false;

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
      pricing: {
        totalCents: parseInt(session.metadata?.totalCents || "2999", 10),
        currency: "usd"
      },
      coverPdfStoragePath: coverStoragePath,
      interiorPdfStoragePath: pdfStoragePath,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      luluTrackingUrl: null,
      luluStatusHistory: []
    };

    await db.collection("users").doc(userId).collection("orders").doc(orderId).set(orderData);

    console.log(`Order ${orderId} saved as 'paid'. Awaiting manual fulfillment.`);
    return res.status(200).json({ received: true, orderId, status: "paid" });
  }
);

// ── Admin: manually submit a paid order to Lulu for printing ──
exports.fulfillOrder = onCall(
  {
    timeoutSeconds: 120,
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

    const orderRef = db.collection("users").doc(targetUserId).collection("orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Order not found");
    }
    const order = orderSnap.data();

    if (order.status !== "paid") {
      throw new HttpsError("failed-precondition", `Order status is '${order.status}', expected 'paid'`);
    }
    if (order.isTestOrder) {
      throw new HttpsError("failed-precondition", "Cannot fulfill a test order");
    }

    const coverStoragePath = order.coverPdfStoragePath;
    const interiorStoragePath = order.interiorPdfStoragePath;
    if (!coverStoragePath || !interiorStoragePath) {
      throw new HttpsError("failed-precondition", "Order missing PDF storage paths");
    }

    const [coverSignedUrl, interiorSignedUrl] = await Promise.all([
      getSignedUrl(coverStoragePath),
      getSignedUrl(interiorStoragePath)
    ]);

    const bookSnap = await db.collection("users").doc(targetUserId)
      .collection("bookVersions").doc(order.bookVersionId).get();
    const bookRecord = bookSnap.exists ? bookSnap.data() : {};
    const firstPageTitle = bookRecord.pages?.[0]?.title || "Story";
    const bookTitle = firstPageTitle ? `${firstPageTitle} (Story)` : "MemoirAI Story";

    const isLandscape = (bookRecord.pageWidth || 612) > (bookRecord.pageHeight || 792);
    const pricingSnap = await db.collection("config").doc("pricing").get();
    const pricingData = pricingSnap.exists ? pricingSnap.data() : {};
    const pricing = isLandscape ? pricingData?.kidsBook : pricingData?.standardBook;
    const podPackageId = pricing?.luluPodPackageId
      ?? (isLandscape ? "1100X0850FCSTDCW080CW444MXX" : "0850X1100FCSTDCW080CW444MXX");

    const shippingAddress = order.shippingAddress || {};
    const payload = {
      line_items: [
        {
          title: bookTitle,
          cover_url: coverSignedUrl,
          interior_url: interiorSignedUrl,
          pod_package_id: podPackageId,
          page_count: bookRecord.pageCount || bookRecord.pages?.length || 0,
          quantity: 1
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
      contact_email: order.customerEmail || "",
      shipping_level: order.shippingLevel || "MAIL",
      external_id: orderId
    };

    const accessToken = await getLuluAccessToken();
    const luluJob = await luluCreatePrintJob(accessToken, payload);
    const luluJobId = luluJob.id || luluJob.external_id;

    await orderRef.update({
      luluPrintJobId: luluJobId,
      status: "submitted_to_printer",
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return { success: true, orderId, luluJobId };
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
    const hist = orderData.luluStatusHistory || [];
    hist.push({ status, timestamp: new Date().toISOString(), trackingUrl: trackingUrl || null });

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
    const ourStatus = statusMap[status] || status;

    const updates = {
      status: ourStatus,
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
