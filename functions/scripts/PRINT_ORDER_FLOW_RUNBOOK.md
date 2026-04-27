# Print order flow — runbook and terminal checks

Use this when validating the full path: **checkout → paid order → fulfillment → Lulu → app history**.

## Prerequisites (one-time)

```bash
gcloud auth application-default login
# Optional quota project (see KIDS_BOOK_PDF_TESTING.md):
# gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

```bash
cd /path/to/MemoirAI/functions
npm install   # if not already — admin scripts need firebase-admin from functions/package.json
```

Set project (default in scripts is `memoirai-7db06`):

```bash
export GCLOUD_PROJECT=memoirai-7db06
```

## Known behavior (read before testing)

0. **`generateBookVersionPdf` (HTTP) cover precondition** — The app triggers server-side PDF packaging when interior pages are uploaded. If the `bookVersions` document has **no `coverURL`** (blank/missing), the function **returns HTTP 409** with `renderStatus` set to `pending` and `renderError` describing missing cover, not a “half-rendered” `rendered` state without a cover. After `COVER_PRECONDITION_MAX_ATTEMPTS` (see `bookVersionPdfGuards.js`) failed preconditions, the function writes `renderStatus: "failed"` and returns **HTTP 200** with `status: "cover_precondition_exhausted"` (not 409) so the client can stop cover-retry churn. The iOS app treats **`coverURL` 409s** by running `ensureCoverDesignExistsIfMissing` and **re-invoking the render function once** (`invokeBookRenderFunction`).

1. **Cart checkout + webhook** — The app uses **`createCartCheckoutSession`** (multi-line cart) and **`stripeWebhook`** on `checkout.session.completed`. Paid cart rows are written under `users/{uid}/orders/{orderId}` with metadata from the pending cart checkout doc.
2. **Auto-fulfill vs test Stripe** — **`autoFulfillPaidOrder`** runs when a new `users/{uid}/orders/{orderId}` document is created with `status === "paid"`, **`isTestOrder !== true`**, and no `luluPrintJobId`. Stripe **test** mode (`event.livemode === false`) sets `isTestOrder: true`, so **Lulu auto-submit is skipped** for test checkouts. Use **live** Stripe (and matching secrets) for a full print submission, or call **`fulfillOrder`** manually where appropriate (it still rejects `isTestOrder`).
3. **Single-book legacy path** — Older flow used **`createCheckoutSession`**; some runbook commands still mention it. Prefer cart logging keys: `createCartCheckoutSession:start`, `pending_written`, `stripe_session_create`. On failure, inspect `users/{uid}/pendingCartCheckouts/{cartOrderGroupId}` for `stripe_create_failed` (cart `cartOrderGroupId` values are short ids like **`book12`**, not `cg_…`).
4. **`admin-orders.js fulfill-confirm`** — May set `pending_fulfillment`, but **`fulfillOrder` requires `status === "paid"`**. Do not assume `fulfill-confirm` is a substitute for a real paid order + `fulfillOrder`.

## Harness commands (recommended)

All commands assume `cd functions`.

### 1) Before payment — preflight

Replace `<bookVersionId>` with the Firestore id under `users/{uid}/bookVersions/{bookVersionId}`.

```bash
./scripts/check-order-flow.sh preflight <bookVersionId>
```

This runs:

- `node scripts/verify-order-setup.js` — `config/pricing`, Firestore access
- `node scripts/check-order-assertions.js preflight <bookVersionId>` — `CHECK_RESULT` lines for render + URLs/paths
- `node scripts/admin-book-pdf.js status <bookVersionId>` — human-readable dump

**Pass criteria:** `CHECK_SUMMARY mode=preflight ok=true` and checkout callable accepts the book in app (same conditions: rendered + PDF + cover).

### 2) After Stripe payment — post-payment

Replace `<orderId>` with the `orderId` field on the order document (e.g. `ord_1700000000_abcd`).

```bash
./scripts/check-order-flow.sh post-payment <orderId>
```

**Pass criteria:** `CHECK_SUMMARY mode=post-payment ok=true`, and Stripe Dashboard shows `checkout.session.completed` delivered to your webhook URL.

**If order not found:** Webhook failed, wrong project, or metadata missing — check `firebase functions:log` for `stripeWebhook`.

### 3) After calling `fulfillOrder` — post-fulfillment

```bash
./scripts/check-order-flow.sh post-fulfillment <orderId>
```

**Pass criteria:** `luluPrintJobId` set, `status` moves past `paid` (e.g. `submitted_to_printer`), and `lulu-status` shows history/tracking when Lulu sends webhooks.

### 4) Watch loop (status + logs)

```bash
./scripts/check-order-flow.sh watch <orderId> 30
```

Polls order status and recent logs every 30 seconds. Requires `firebase-tools` for logs (`firebase functions:log`).

## Manual equivalents (without harness)

```bash
node scripts/verify-order-setup.js
node scripts/check-order-assertions.js preflight <bookVersionId>
node scripts/admin-book-pdf.js status <bookVersionId>

node scripts/check-order-assertions.js post-payment <orderId>
node scripts/admin-book-pdf.js orders status <orderId>
GCLOUD_PROJECT=$GCLOUD_PROJECT node scripts/admin-orders.js list paid

node scripts/check-order-assertions.js post-fulfillment <orderId>
node scripts/check-order-assertions.js lulu-status <orderId>
```

## Firebase function logs (read-only)

```bash
firebase functions:log -n 50 --only stripeWebhook,luluWebhook,fulfillOrder,createCheckoutSession,createCartCheckoutSession,createCartCheckoutSessionFast,prepareCartCheckoutQuote,estimateCartCheckoutPricing --project "$GCLOUD_PROJECT"
```

## Evidence to paste back (for debugging)

See `./scripts/check-order-flow.sh help` — prints **EVIDENCE_TEMPLATE** at the end.

Minimum:

1. Full terminal output of `preflight`, `post-payment`, and `post-fulfillment` for your IDs.
2. `bookVersionId`, `orderId`, `stripeSessionId`, `luluPrintJobId` when available.
3. One Stripe Dashboard screenshot or note that `checkout.session.completed` was delivered.
4. App Order History screenshot for the same order.

## Machine-readable lines

Assertions print lines like:

```text
CHECK_RESULT milestone=preflight name=renderStatus_rendered ok=true detail="rendered"
CHECK_SUMMARY mode=preflight ok=true
```

You can grep or save logs for CI later.
