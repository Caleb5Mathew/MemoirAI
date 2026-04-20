#!/bin/bash
# Sets up Firebase secrets for book ordering.
# Run from project root: ./scripts/setup-book-ordering-secrets.sh
# You'll be prompted to paste each secret when requested.

set -e

echo "MemoirAI Book Ordering - Firebase Secrets Setup"
echo "================================================"
echo ""

echo "1/5 STRIPE_SECRET_KEY (sk_test_... or sk_live_...)"
firebase functions:secrets:set STRIPE_SECRET_KEY

echo ""
echo "2/5 STRIPE_WEBHOOK_SECRET (whsec_...)"
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET

echo ""
echo "3/5 LULU_CLIENT_KEY"
firebase functions:secrets:set LULU_CLIENT_KEY

echo ""
echo "4/5 LULU_CLIENT_SECRET"
firebase functions:secrets:set LULU_CLIENT_SECRET

echo ""
echo "5/5 LULU_WEBHOOK_SECRET (or press Enter to skip if not used)"
firebase functions:secrets:set LULU_WEBHOOK_SECRET || true

echo ""
echo "✅ All secrets set. Deploy functions: firebase deploy --only functions"
