#!/usr/bin/env bash
# Stripe + Firebase readiness gates (read-only / local checks).
# Run from repo root: ./scripts/stripe-readiness-gates.sh
#
# Does NOT set secrets or call Stripe APIs. Use the printed checklist for
# Dashboard + production verification after deploy.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${FIREBASE_PROJECT:-${GCLOUD_PROJECT:-memoirai-7db06}}"

echo "=== Stripe / print-order readiness (local gates) ==="
echo "Project: ${PROJECT_ID}"
echo ""

fail=0

if [[ ! -f "${ROOT}/firebase.json" ]]; then
  echo "❌ firebase.json missing at repo root"
  fail=1
else
  echo "✅ firebase.json present"
fi

if [[ ! -f "${ROOT}/firestore.indexes.json" ]]; then
  echo "❌ firestore.indexes.json missing"
  fail=1
else
  if grep -q 'pendingCartCheckouts' "${ROOT}/firestore.indexes.json" 2>/dev/null; then
    echo "✅ Firestore index for pendingCartCheckouts (reconcile job) present in repo"
  else
    echo "⚠️  Expected collectionGroup index for pendingCartCheckouts — check firestore.indexes.json"
  fi
fi

if [[ ! -f "${ROOT}/functions/index.js" ]]; then
  echo "❌ functions/index.js missing"
  fail=1
else
  echo "✅ functions/index.js present"
fi

FB=""
if command -v firebase >/dev/null 2>&1; then
  FB="firebase"
elif command -v npx >/dev/null 2>&1; then
  FB="npx firebase-tools"
fi

if [[ -n "$FB" ]]; then
  echo ""
  echo "--- Firebase CLI (${FB}) ---"
  if $FB --version 2>/dev/null; then
    echo "✅ Firebase CLI available"
  fi
  echo ""
  echo "Optional (requires login): list recent logs for Stripe + checkout:"
  echo "  $FB functions:log -n 40 --only stripeWebhook,createCartCheckoutSession,createCartCheckoutSessionFast,prepareCartCheckoutQuote --project ${PROJECT_ID}"
else
  echo "⚠️  firebase-tools not found; install: npm i -g firebase-tools"
fi

echo ""
echo "=== Manual gates (production) ==="
echo "1. Firebase Console → Functions: stripeWebhook, createCartCheckoutSessionFast, prepareCartCheckoutQuote deployed."
echo "2. Stripe Dashboard (same mode as STRIPE_SECRET_KEY): Webhooks → endpoint → checkout.session.completed → recent deliveries 2xx."
echo "3. Secrets: STRIPE_SECRET_KEY prefix (sk_test_ vs sk_live_) matches webhook mode; STRIPE_WEBHOOK_SECRET from that endpoint only."
echo "4. E2E: run from functions/: ./scripts/check-order-flow.sh preflight <bookVersionId>"
echo "5. After a test payment: ./scripts/check-order-flow.sh post-payment <orderId>"
echo ""
echo "Full checklist: STRIPE_GO_LIVE_CHECKLIST.md"
echo ""

exit "$fail"
