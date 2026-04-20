# Book Ordering Setup Guide

This guide covers the manual setup required before the book ordering system can be used.

**Simulator vs App Store checkout behavior, App Check/FCM noise, webhook verification, and release acceptance matrix:** see [`STRIPE_CHECKOUT_READINESS.md`](STRIPE_CHECKOUT_READINESS.md).

## Quick Start (Minimal Steps)

1. **Create accounts** – Stripe, Lulu (prod + sandbox) – see Phase 0A below.
2. **Set secrets** – Run once: `./scripts/setup-book-ordering-secrets.sh` (paste each value when prompted).
3. **Seed pricing** – Run once: `cd functions && node scripts/seed-pricing-config.js`
4. **Deploy** – `firebase deploy --only functions,firestore:rules,firestore:indexes` (ships fast checkout: `prepareCartCheckoutQuote`, `createCartCheckoutSessionFast`, scheduled `reconcilePendingCartCheckouts`, plus existing `createCartCheckoutSession` / `estimateCartCheckoutPricing`).
5. **Verify** – `cd functions && node scripts/verify-order-setup.js`

**Full E2E verification (preflight → payment → fulfillment):** see [`functions/scripts/PRINT_ORDER_FLOW_RUNBOOK.md`](functions/scripts/PRINT_ORDER_FLOW_RUNBOOK.md). From `functions/`: `./scripts/check-order-flow.sh help`.

Admin tools: `cd functions && node scripts/admin-book-pdf.js help`

## Phase 0A: Create Accounts

### Stripe

1. Sign up at [stripe.com](https://stripe.com)
2. Get your API keys from Dashboard > Developers > API keys:
   - **Publishable key** (pk_test_... for testing, pk_live_... for production)
   - **Secret key** (sk_test_... for testing, sk_live_... for production)
3. Create a webhook endpoint:
   - Dashboard > Developers > Webhooks > Add endpoint
   - URL: `https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/stripeWebhook`
     (Replace YOUR_PROJECT_ID with your Firebase project ID, e.g. memoirai-7db06)
   - Events: `checkout.session.completed`
   - Copy the **Webhook signing secret** (whsec_...)

### Lulu Developer

1. Sign up at [developers.lulu.com](https://developers.lulu.com) (production)
2. Sign up at [developers.sandbox.lulu.com](https://developers.sandbox.lulu.com) (testing)
3. From your profile > API Keys, copy:
   - **Client Key**
   - **Client Secret**
4. Create a webhook in the Lulu developer portal:
   - URL: `https://us-central1-memoirai-7db06.cloudfunctions.net/luluWebhook`
   - Topic: `PRINT_JOB_STATUS_CHANGED`
   - Copy the webhook secret if provided

### Lulu pod_package_id (11x8.5 Hardcover Matte)

Use the [Lulu Pricing Calculator](https://lulu.com/pricing) or [Lulu Print API Products](https://www.lulu.com/print-api/products) to find the exact 27-character SKU.

For 11x8.5" landscape, hardcover casewrap, full color, standard (not premium) color paper, matte finish:
- Trim: `1100X0850` (11" x 8.5")
- Format: `FC` (full color) + `STD` (standard) + `CW` (casewrap) + paper + `M` (matte) + `XX` (no linen/foil)

Example format: `1100X0850FCSTDCW080CW444MXX` (verify via Lulu API or calculator).

## Phase 0B: Configure Firebase Secret/Environment

Add these secrets to Firebase (for Cloud Functions):

```bash
./scripts/setup-book-ordering-secrets.sh
```

Or manually:
```bash
firebase functions:secrets:set STRIPE_SECRET_KEY
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
firebase functions:secrets:set LULU_CLIENT_KEY
firebase functions:secrets:set LULU_CLIENT_SECRET
firebase functions:secrets:set LULU_WEBHOOK_SECRET
```

For local testing with Lulu sandbox, set the env var when running the emulator:
```bash
LULU_USE_SANDBOX=true firebase emulators:start --only functions
```

## Seed Firestore config/pricing

Run the seed script (recommended):
```bash
cd functions && node scripts/seed-pricing-config.js
```

Or create a document at `config/pricing` in Firestore manually with:

```json
{
  "kidsBook": {
    "luluPodPackageId": "1100X0850FCSTDCW080CW444MXX",
    "basePriceCents": 2999,
    "currency": "usd",
    "marginPercent": 30,
    "description": "11x8.5 Hardcover Kids Book, Full Color, Matte"
  }
}
```

Replace `luluPodPackageId` with the exact SKU from Lulu's calculator if different.

## Going Live (Production Stripe)

When ready for real payments:

1. Complete Stripe identity verification (Dashboard > complete any "required tasks").
2. In Stripe Dashboard, switch to **Live** mode (toggle in sidebar).
3. Create a **new** webhook endpoint (live mode uses a different signing secret):
   - URL: `https://us-central1-memoirai-7db06.cloudfunctions.net/stripeWebhook`
   - Events: `checkout.session.completed`
   - Copy the signing secret (whsec_...).
4. Enable receipt emails: Dashboard > Settings > Emails > "Successful payments".
5. Set **live** secrets (never commit keys). The swap script reads `sk_live_...` from **`STRIPE_LIVE_SECRET_KEY`** or a hidden prompt — not from source control:
   ```bash
   export STRIPE_LIVE_SECRET_KEY=sk_live_...   # paste from Stripe Dashboard (Live)
   ./scripts/swap-to-live-stripe.sh whsec_YOUR_LIVE_SECRET
   ```
6. Redeploy: `npx firebase-tools deploy --only functions --project memoirai-7db06`
7. Optional local gates: `./scripts/stripe-readiness-gates.sh` — see [`STRIPE_GO_LIVE_CHECKLIST.md`](STRIPE_GO_LIVE_CHECKLIST.md).

Note: Test mode and live mode use different webhook secrets. Do not reuse the test webhook secret for live.

## iOS Info.plist

The current app uses **hosted Stripe Checkout** (session URL from Cloud Functions). The **publishable key is not required** in the client for that flow. If you add Stripe SDK features later, you could add `StripePublishableKey` (`pk_test_` / `pk_live_`) — keep it in sync with the same Stripe mode as your backend secrets.
