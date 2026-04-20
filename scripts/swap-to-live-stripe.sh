#!/bin/bash
# Swap Stripe secrets to LIVE mode for production.
# Run after creating a LIVE webhook in Stripe Dashboard.
#
# NEVER commit or paste live keys into this file. Keys are read from the
# environment or an interactive prompt only.
#
# Prerequisites:
#   - firebase-tools (npx firebase-tools works)
#   - Logged in: firebase login
#
# Usage:
#   export STRIPE_LIVE_SECRET_KEY=sk_live_...   # or STRIPE_SECRET_KEY
#   ./scripts/swap-to-live-stripe.sh whsec_YOUR_LIVE_WEBHOOK_SECRET
#
# Or omit env vars and paste when prompted (stdin is hidden).
#
# Stripe Dashboard (Live mode):
#   1. Developers > Webhooks > Add endpoint
#   2. URL: https://us-central1-<PROJECT_ID>.cloudfunctions.net/stripeWebhook
#   3. Events: checkout.session.completed
#   4. Copy signing secret (whsec_...)

set -euo pipefail

PROJECT_ID="${FIREBASE_PROJECT:-${GCLOUD_PROJECT:-memoirai-7db06}}"
WEBHOOK_SECRET="${1:-}"

usage() {
  echo "Usage: $0 <LIVE_WEBHOOK_SECRET>"
  echo ""
  echo "Set the live Stripe secret key via environment (recommended):"
  echo "  export STRIPE_LIVE_SECRET_KEY=sk_live_..."
  echo "  $0 whsec_..."
  echo ""
  echo "Alternatively STRIPE_SECRET_KEY may be set to the sk_live_ value."
  echo "If neither is set, you will be prompted (input hidden)."
  echo ""
  echo "Project: ${PROJECT_ID} (override with FIREBASE_PROJECT or GCLOUD_PROJECT)"
  exit 1
}

if [ -z "$WEBHOOK_SECRET" ]; then
  usage
fi

resolve_live_secret_key() {
  local raw=""
  if [ -n "${STRIPE_LIVE_SECRET_KEY:-}" ]; then
    raw="$STRIPE_LIVE_SECRET_KEY"
  elif [ -n "${STRIPE_SECRET_KEY:-}" ] && [[ "${STRIPE_SECRET_KEY}" == sk_live_* ]]; then
    raw="$STRIPE_SECRET_KEY"
  else
    echo "Paste LIVE Stripe secret key (sk_live_...); input is hidden:"
    read -rs raw
    echo ""
  fi

  raw="$(printf '%s' "$raw" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ ! "$raw" =~ ^sk_live_ ]]; then
    echo "Error: secret must be a LIVE key starting with sk_live_ (got prefix: ${raw:0:12}...)" >&2
    exit 1
  fi
  printf '%s' "$raw"
}

LIVE_KEY="$(resolve_live_secret_key)"

echo "Setting STRIPE_SECRET_KEY (live) for project ${PROJECT_ID}..."
printf '%s' "$LIVE_KEY" | npx firebase-tools functions:secrets:set STRIPE_SECRET_KEY --project "$PROJECT_ID"

echo "Setting STRIPE_WEBHOOK_SECRET (live webhook signing secret)..."
printf '%s' "$WEBHOOK_SECRET" | npx firebase-tools functions:secrets:set STRIPE_WEBHOOK_SECRET --project "$PROJECT_ID"

echo ""
echo "Done. Redeploy functions so new secrets bind:"
echo "  npx firebase-tools deploy --only functions --project $PROJECT_ID"
