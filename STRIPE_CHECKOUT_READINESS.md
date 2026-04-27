# Stripe checkout: simulator vs production readiness

This doc matches the shipped flow: **Order Print** → live Lulu pricing + checkout quote (`prepareCartCheckoutQuote`) → **Stripe Checkout** via the fast path (`createCartCheckoutSessionFast` when enabled) with automatic fallback to the legacy callable (`createCartCheckoutSession`) → deep link `memoirai://order-complete`.

### Fast checkout (recommended)

- **Prepare quote** (`prepareCartCheckoutQuote`): runs Lulu line + whole-order shipping once, stores `users/{uid}/checkoutQuotes/{quoteId}` (TTL ~30 minutes), returns `quoteId`, `cartHash`, `expiresAtMillis`, and the same estimate fields the UI already uses.
- **Pay** (`createCartCheckoutSessionFast`): validates the quote, writes `pendingCartCheckouts`, creates the Stripe session only (no Lulu work). Each attempt uses a short per-user id **`book{N}`** (monotonic counter in `users/{uid}/_checkoutSeq/v`) as the Firestore document id for **`checkoutAttempts/{bookN}`** and **`pendingCartCheckouts/{bookN}`**, and as `metadata.cartOrderGroupId` for the Stripe session. Optional **`checkoutInstanceId`** on the callable resumes that same attempt; the app may send **`clientCorrelationId`** (e.g. UUID) for logging only.
- **Disable server-side** (emergency): set `FAST_CHECKOUT_ENABLED=false` on the Functions runtime → `createCartCheckoutSessionFast` returns `failed-precondition` and the app falls back to `createCartCheckoutSession`.
- **Reconciliation**: scheduled function `reconcilePendingCartCheckouts` (every 15 minutes) marks stale `pending_stripe` sessions when Stripe reports `expired` (requires Firestore composite index on collection group `pendingCartCheckouts`: `status` + `createdAt`).

## Simulator: what is normal noise?

| Log / symptom | Meaning |
|---------------|--------|
| `App Check failed: ... DeviceCheckProvider is not supported` | Device Check does not run on Simulator. The app only registers `DeviceCheckProvider` on **device**; on Simulator, with default settings, **no App Check provider** is set unless you opt in (`MemoirAI_EnableAppCheckDebug`). Console noise can still appear from **Firestore** or other SDK paths. It does **not** block callables unless you **enforce** App Check in Firebase Console without registering a **debug** token. |
| `Declining request for FCM Token since no APNS Token` | Messaging expects APNS. Common on Simulator / before remote notification registration. **Unrelated** to Stripe checkout (ordering does not use FCM). |
| `nw_connection_copy_connected_local_endpoint...` | Transient URLSession / network stack logs; usually harmless. |

## Production / App Store checklist (secrets & webhook)

1. **Secrets** (Firebase Functions) — see [`ORDER_SETUP_GUIDE.md`](ORDER_SETUP_GUIDE.md):
   - `STRIPE_SECRET_KEY` (use **live** `sk_live_…` for real charges)
   - `STRIPE_WEBHOOK_SECRET` (`whsec_…` for the **same** Stripe mode as the secret key)
   - `LULU_CLIENT_KEY` / `LULU_CLIENT_SECRET` (match sandbox vs prod with `LULU_USE_SANDBOX` / deployment config)

2. **Stripe webhook URL** (Dashboard → Webhooks):
   - Endpoint: `https://<region>-<PROJECT_ID>.cloudfunctions.net/stripeWebhook`
   - Event: `checkout.session.completed`
   - After deploy, use **Send test webhook** and confirm **2xx** in Stripe and a corresponding line in `firebase functions:log --only stripeWebhook`.

3. **Stripe mode vs Lulu fulfillment**
   - Webhook sets `isTestOrder` from `event.livemode === false`.
   - **`autoFulfillPaidOrder`** (on `users/{uid}/orders/{orderId}`) **skips** Lulu when `isTestOrder` is true. So **test-mode** Stripe can complete payment and create `paid` orders but **not** auto-submit to Lulu.
   - For a **real** print submission, use **live** Stripe keys and live checkout, or exercise fulfillment explicitly in a controlled environment.

## Correlating failures (`INTERNAL` in app)

When checkout fails, the app shows a user-safe message; **Debug** builds also log and show a `DEBUG fn=createCartCheckoutSession …` line.

**Cloud Logging** (deployed `createCartCheckoutSession`):

- Structured lines: `createCartCheckoutSession:start`, `pending_written`, `stripe_session_create`, or `stripe session create failed`.
- Every attempt logs **`cartOrderGroupId`** at start.
- On Stripe failure, Firestore may contain: `users/<uid>/pendingCartCheckouts/<cartOrderGroupId>` with `status: "stripe_create_failed"` and `stripeError`.

**Grep logs** (example):

```bash
firebase functions:log -n 80 --only createCartCheckoutSessionFast,createCartCheckoutSession,prepareCartCheckoutQuote,stripeWebhook --project YOUR_PROJECT_ID
```

**Local gates (repo sanity):** `./scripts/stripe-readiness-gates.sh` — full pass/fail table: [`STRIPE_GO_LIVE_CHECKLIST.md`](STRIPE_GO_LIVE_CHECKLIST.md).

## Acceptance matrix (release parity)

Run these before treating App Store checkout as “done.”

| Step | Simulator | Physical device / TestFlight |
|------|-----------|-------------------------------|
| Signed in | Required | Required |
| Order Print → estimate | Should show Lulu-backed total (or documented fallback) | Same |
| Checkout → Safari / Stripe page | Opens checkout URL | Same |
| Complete test payment | Allowed with Stripe **test mode** (`sk_test_` server secret); session opened in Safari | Prefer internal TestFlight + [Stripe test cards](https://docs.stripe.com/testing) |
| Return URL | App handles `memoirai://order-complete` (see `MemoirAIApp.swift`) | Same; confirm URL scheme in **Release** build |
| Firestore | Optional: confirm `pendingCartCheckouts` / `orders` if webhook runs | Same |
| Lulu auto-fulfill | Only if **live** Stripe → `isTestOrder == false` | Validate on staging with live-mode policy |

**Automated coverage:** unit tests in `MemoirAITests/OrderCallableErrorFormattingTests.swift` lock friendly messaging for callable `INTERNAL` errors.

## Related docs

- [`STRIPE_GO_LIVE_CHECKLIST.md`](STRIPE_GO_LIVE_CHECKLIST.md) — App Store / production pass-fail gates  
- [`ORDER_SETUP_GUIDE.md`](ORDER_SETUP_GUIDE.md) — secrets, deploy, seed pricing  
- [`functions/scripts/PRINT_ORDER_FLOW_RUNBOOK.md`](functions/scripts/PRINT_ORDER_FLOW_RUNBOOK.md) — preflight / post-payment CLI checks  
