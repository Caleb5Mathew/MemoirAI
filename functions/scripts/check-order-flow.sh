#!/usr/bin/env bash
#
# Print order flow verification harness — wraps verify-order-setup, admin-book-pdf,
# admin-orders, check-order-assertions, and optional Firebase function logs.
#
# Usage (from repo root or from functions/):
#   ./functions/scripts/check-order-flow.sh help
#   cd functions && ./scripts/check-order-flow.sh preflight <bookVersionId>
#   cd functions && ./scripts/check-order-flow.sh post-payment <orderId>
#   cd functions && ./scripts/check-order-flow.sh post-fulfillment <orderId>
#   cd functions && ./scripts/check-order-flow.sh watch <orderId> [intervalSeconds]
#
# Requires: Node.js, firebase-admin (functions/node_modules), Application Default Credentials:
#   gcloud auth application-default login
#
# Env:
#   GCLOUD_PROJECT   Firebase/GCP project id (default: memoirai-7db06)
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
export GCLOUD_PROJECT="${GCLOUD_PROJECT:-memoirai-7db06}"
cd "${FUNCS_DIR}"

NODE="${NODE:-node}"
FIREBASE="${FIREBASE:-firebase}"

usage() {
  cat <<'EOF'
Print Order Flow — verification harness

Commands:
  help
      Show this message and the evidence template.

  preflight <bookVersionId>
      - Runs verify-order-setup.js (pricing / Firestore sanity)
      - Runs check-order-assertions.js preflight (rendered + paths/URLs)
      - Prints admin-book-pdf.js status (human-readable detail)

  post-payment <orderId>
      - Runs check-order-assertions.js post-payment (paid order shape)
      - Prints admin-book-pdf.js orders status (human-readable)

  post-fulfillment <orderId>
      - Runs check-order-assertions.js post-fulfillment (Lulu job + status)
      - Runs check-order-assertions.js lulu-status (history / tracking snapshot)

  watch <orderId> [intervalSeconds]
      - Loops: order status snapshot + recent function logs (stripeWebhook, luluWebhook, fulfillOrder, createCheckoutSession)
      - Default interval: 30 seconds. Ctrl+C to stop.

Environment:
  GCLOUD_PROJECT    (default: memoirai-7db06)

Runbook:
  See functions/scripts/PRINT_ORDER_FLOW_RUNBOOK.md

EOF
}

print_evidence_template() {
  cat <<'EOF'

--- EVIDENCE_TEMPLATE (paste back for review) ---
GCLOUD_PROJECT=
bookVersionId=
orderId=
stripeSessionId=   (from order doc or Stripe Dashboard)
luluPrintJobId=    (after fulfillment)

1) preflight output (full terminal block)
2) post-payment output (full terminal block)
3) post-fulfillment + lulu-status output
4) watch excerpt (last 2–3 cycles) OR firebase functions:log snippet
5) Stripe: Dashboard → Developers → Webhooks → checkout.session.completed (delivered)
6) App: Order History screenshot (paid + later status if applicable)

--- END ---

EOF
}

run_preflight() {
  local bv="${1:?bookVersionId required}"
  local code=0
  echo ""
  echo "========== STEP: verify-order-setup =========="
  "${NODE}" scripts/verify-order-setup.js || code=1
  echo "========== STEP: check-order-assertions preflight =========="
  "${NODE}" scripts/check-order-assertions.js preflight "${bv}" || code=1
  echo "========== STEP: admin-book-pdf status (detail) =========="
  "${NODE}" scripts/admin-book-pdf.js status "${bv}" || true
  exit "${code}"
}

run_post_payment() {
  local oid="${1:?orderId required}"
  local code=0
  echo ""
  echo "========== STEP: check-order-assertions post-payment =========="
  "${NODE}" scripts/check-order-assertions.js post-payment "${oid}" || code=1
  echo "========== STEP: admin-book-pdf orders status =========="
  "${NODE}" scripts/admin-book-pdf.js orders status "${oid}" || true
  exit "${code}"
}

run_post_fulfillment() {
  local oid="${1:?orderId required}"
  local code=0
  echo ""
  echo "========== STEP: check-order-assertions post-fulfillment =========="
  "${NODE}" scripts/check-order-assertions.js post-fulfillment "${oid}" || code=1
  echo "========== STEP: check-order-assertions lulu-status =========="
  "${NODE}" scripts/check-order-assertions.js lulu-status "${oid}" || true
  exit "${code}"
}

run_watch() {
  local oid="${1:?orderId required}"
  local interval="${2:-30}"
  echo ""
  echo "Watching order ${oid} every ${interval}s (Ctrl+C to stop)"
  echo "Project: ${GCLOUD_PROJECT}"
  while true; do
    echo ""
    echo "---------- $(date -u +"%Y-%m-%dT%H:%M:%SZ") ----------"
    "${NODE}" scripts/admin-book-pdf.js orders status "${oid}" || true
    if command -v "${FIREBASE}" >/dev/null 2>&1; then
      echo ""
      echo "--- firebase functions:log (last 12 lines, filtered) ---"
      "${FIREBASE}" functions:log -n 12 --only stripeWebhook,luluWebhook,fulfillOrder,createCheckoutSession,createCartCheckoutSession,createCartCheckoutSessionFast,prepareCartCheckoutQuote --project "${GCLOUD_PROJECT}" 2>/dev/null || true
    else
      echo "(firebase CLI not found; skip logs). Install: npm i -g firebase-tools"
    fi
    sleep "${interval}"
  done
}

case "${1:-help}" in
  help|-h|--help|"")
    usage
    print_evidence_template
    ;;
  preflight)
    run_preflight "${2:-}"
    ;;
  post-payment)
    run_post_payment "${2:-}"
    ;;
  post-fulfillment)
    run_post_fulfillment "${2:-}"
    ;;
  watch)
    run_watch "${2:-}" "${3:-30}"
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage
    exit 1
    ;;
esac
