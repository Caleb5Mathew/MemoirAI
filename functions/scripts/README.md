# MemoirAI Admin Scripts

## admin-book-pdf.js

List books, check render status, trigger PDF generation, and download PDFs.

### Requirements

- Node.js
- Firebase project `memoirai-7db06`
- **Application Default Credentials** for Firestore/Storage access:

  ```bash
  # Install Google Cloud SDK, then:
  gcloud auth application-default login
  ```

  If you use `firebase login`, that authenticates the Firebase CLI but not the Node.js Admin SDK. You need ADC for this script.

### Usage

```bash
cd functions
node scripts/admin-book-pdf.js list
node scripts/admin-book-pdf.js list <userId>
node scripts/admin-book-pdf.js status <bookVersionId>
node scripts/admin-book-pdf.js trigger <bookVersionId> [userId]
node scripts/admin-book-pdf.js download <bookVersionId> [outputPath]
node scripts/admin-book-pdf.js verify <bookVersionId>   # Download, validate PDF structure
```

### Examples

```bash
# List all recent books
node scripts/admin-book-pdf.js list

# List books for one user
node scripts/admin-book-pdf.js list GvgDuJiXL5YCdalwy9999Tr9MrS2

# Check why a book hasn't rendered
node scripts/admin-book-pdf.js status 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420

# Generate PDF for a book (finds user automatically)
node scripts/admin-book-pdf.js trigger 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420

# Download PDF to current directory
node scripts/admin-book-pdf.js download 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420

# Download to specific path
node scripts/admin-book-pdf.js download 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420 ./print/MyBook.pdf

# Verify PDF (page count, dimensions)
node scripts/admin-book-pdf.js verify 07740D04-44D1-4AB3-8EAE-357E26D16824_1771969420
```

## Print order flow verification

End-to-end checks for Stripe checkout → Firestore `paid` order → Lulu fulfillment → status updates.

- **Runbook (step-by-step):** [PRINT_ORDER_FLOW_RUNBOOK.md](./PRINT_ORDER_FLOW_RUNBOOK.md)
- **Harness (shell):** `scripts/check-order-flow.sh` — modes `preflight`, `post-payment`, `post-fulfillment`, `watch`, `help`
- **Assertions (Node):** `scripts/check-order-assertions.js` — prints `CHECK_RESULT` lines; used by the harness

Quick start (from `functions/`):

```bash
chmod +x scripts/check-order-flow.sh   # once
export GCLOUD_PROJECT=memoirai-7db06
./scripts/check-order-flow.sh help
./scripts/check-order-flow.sh preflight <bookVersionId>
```

See also: `verify-order-setup.js`, `admin-orders.js`, and `ORDER_SETUP_GUIDE.md` at repo root.
