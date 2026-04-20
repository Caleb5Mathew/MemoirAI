# Stripe + print orders — go-live checklist

Use this before App Store submission when **real book orders** must work. Hosted Stripe Checkout is implemented server-side; the iOS app only opens the checkout URL and handles `memoirai://` return URLs.

**Reference:** [Stripe API keys (test vs live)](https://docs.stripe.com/keys)

## Pass / fail criteria

| Gate | Pass | Fail |
|------|------|------|
| Mode match | `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` are both **test** or both **live** | Mixed modes (e.g. live key + test `whsec_`) |
| Webhook | Stripe shows `checkout.session.completed` **delivered** (2xx) to your function URL | 4xx/5xx, or no deliveries |
| Callable deploy | `prepareCartCheckoutQuote`, `createCartCheckoutSessionFast` (or legacy `createCartCheckoutSession`) exist in Firebase | `NOT FOUND` / checkout errors |
| Post-payment | Firestore `users/{uid}/orders/{orderId}` has `status: paid`, PDF paths, `stripeSessionId` | No order doc after payment |
| Live printing | For **live** Stripe: `isTestOrder: false` and eventually `luluPrintJobId` (or clear error in logs) | Stuck `paid` forever with no job and no errors |

## Simulator — expected behavior (Review → Checkout)

1. User must be **signed in** (Firebase Auth).
2. Tapping **Checkout** calls Cloud Functions to create a Stripe Checkout **session**; the app opens the returned URL in **Safari** (`SFSafariViewController`).
3. **Test mode:** Pay with a [Stripe test card](https://docs.stripe.com/testing). No real charge.
4. On success, Stripe redirects to **`memoirai://order-complete?session_id=...`**. The app stores the session id, clears the cart, and dismisses the order flow.
5. **App Check:** On Simulator, Device Check is unavailable; see [`STRIPE_CHECKOUT_READINESS.md`](STRIPE_CHECKOUT_READINESS.md) if you enforce App Check without a debug token.
6. **Test Stripe:** Webhook sets `isTestOrder: true`. **`autoFulfillPaidOrder` does not submit to Lulu** for test orders. That is expected.

## Production — one-time setup

1. Complete Stripe account requirements (verification, any Dashboard tasks).
2. **Live** Stripe: toggle Live mode → create **live** restricted or standard secret key → set Firebase secret `STRIPE_SECRET_KEY` (never commit keys).
3. **Live webhook:** Developers → Webhooks → Add endpoint  
   - URL: `https://us-central1-<PROJECT_ID>.cloudfunctions.net/stripeWebhook`  
   - Event: `checkout.session.completed`  
   - Copy **`whsec_...`** for **that** endpoint into `STRIPE_WEBHOOK_SECRET`.
4. Run [`scripts/swap-to-live-stripe.sh`](scripts/swap-to-live-stripe.sh) **or** set secrets manually — script requires `STRIPE_LIVE_SECRET_KEY` (or interactive paste), **not** a key baked into the repo.
5. Deploy: `firebase deploy --only functions,firestore:indexes` (indexes include `pendingCartCheckouts` for reconciliation).

## Verification commands

Local sanity (no credentials required beyond optional Firebase login):

```bash
./scripts/stripe-readiness-gates.sh
```

Preflight / post-payment (see [`functions/scripts/PRINT_ORDER_FLOW_RUNBOOK.md`](functions/scripts/PRINT_ORDER_FLOW_RUNBOOK.md)):

```bash
cd functions
export GCLOUD_PROJECT=your-project-id   # default in scripts: memoirai-7db06
./scripts/check-order-flow.sh preflight <bookVersionId>
# after a real test checkout:
./scripts/check-order-flow.sh post-payment <orderId>
```

Stripe Dashboard: Webhooks → select endpoint → **Recent deliveries** → confirm `checkout.session.completed` succeeded.

Firebase logs:

```bash
firebase functions:log -n 50 --only stripeWebhook,createCartCheckoutSessionFast,prepareCartCheckoutQuote --project YOUR_PROJECT_ID
```

## Related docs

- [`STRIPE_CHECKOUT_READINESS.md`](STRIPE_CHECKOUT_READINESS.md) — fast checkout, simulator noise, correlation IDs  
- [`ORDER_SETUP_GUIDE.md`](ORDER_SETUP_GUIDE.md) — secrets, Lulu, seed pricing
