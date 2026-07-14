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
   - Events: `checkout.session.completed`, `charge.refunded`, `charge.dispute.created` (the last two flag `refundStatus`/`disputeStatus`/`fulfillmentHold` on the affected order docs — they will never fire if not added here, since Stripe only sends the event types an endpoint is subscribed to)  
   - Copy **`whsec_...`** for **that** endpoint into `STRIPE_WEBHOOK_SECRET`.
4. Run [`scripts/swap-to-live-stripe.sh`](scripts/swap-to-live-stripe.sh) **or** set secrets manually — script requires `STRIPE_LIVE_SECRET_KEY` (or interactive paste), **not** a key baked into the repo.
5. Deploy: `firebase deploy --only functions,firestore:indexes` (indexes include `pendingCartCheckouts` for reconciliation).
6. **Stripe Dashboard receipts:** Settings → Emails → turn on **Successful payments** so the customer gets a Stripe receipt independent of anything MemoirAI sends. This is separate from the ops alerts below (those go to Caleb, not the customer).

## Ops alert emails

`functions/opsAlerts.js` emails **memoirstorybook@gmail.com** when: a cart checkout is paid, an order fails to submit to Lulu (`lulu_failed`), or a refund/dispute webhook fires. Env-gated via the `OPS_ALERT_SMTP_URL` secret — while unset, `sendOpsAlert` just logs `ops alert skipped (OPS_ALERT_SMTP_URL not configured)` and every function behaves exactly as before (same pattern as `ENFORCE_APP_CHECK`).

**One-time setup (Gmail app password):**

1. The sending Gmail account needs 2-Step Verification on: [myaccount.google.com/security](https://myaccount.google.com/security) → **2-Step Verification** → enable.
2. Create an app password: [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) → app name "MemoirAI Ops Alerts" → copy the 16-character password.
3. Build the SMTP URL: `smtps://<url-encoded-email>:<app-password>@smtp.gmail.com:465`  
   (URL-encode `@` in the address as `%40`, e.g. `smtps://memoirstorybook%40gmail.com:abcdxyzabcdxyzab@smtp.gmail.com:465`.)
4. Set the Firebase secret: `firebase functions:secrets:set OPS_ALERT_SMTP_URL` (paste the URL from step 3 when prompted).
5. Deploy: `firebase deploy --only functions`.
6. Verify: trigger a test checkout (or `firebase functions:log --only stripeWebhook`) and confirm `ops alert sent: New paid order …` appears instead of the skipped-warning.

You can reuse the same Gmail account, or a dedicated one — either way it only needs to be able to send mail, not receive.

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

## App Check rollout

`ENFORCE_APP_CHECK` (see `functions/.env`, default `false`) gates App Check enforcement on the payment callables (`estimateCheckoutPricing`, `estimateCartCheckoutPricing`, `prepareCartCheckoutQuote`, `createCartCheckoutSessionFast`, `createCheckoutSession`, `createCartCheckoutSession`) and the AI proxy callables (`aiChatCompletion`, `aiGenerateCoverArt`, `aiEditImage`). While `false`, these callables behave exactly as before — no client change required yet.

Flip procedure once the iOS client is ready:

1. Register the iOS app for **App Attest** in the Firebase console (Project settings → App Check → apps → Register).
2. Ship an iOS build that initializes the Firebase App Check SDK (App Attest provider) before making any callable request.
3. Let it run for a burn-in period with `ENFORCE_APP_CHECK=false` — watch the App Check **Metrics** tab in the Firebase console for verified vs. unverified request ratios to confirm the App Store build population has adopted the SDK.
4. Set `ENFORCE_APP_CHECK=true` in `functions/.env`.
5. Deploy: `firebase deploy --only functions`.
6. Watch `firebase functions:log` for `permission-denied` App Check rejections for a day before considering the rollout complete — a spike means an unsupported client (old build, simulator without a debug token) is still in the field.
