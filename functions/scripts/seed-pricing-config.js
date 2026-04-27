#!/usr/bin/env node
/**
 * Seeds the config/pricing document in Firestore.
 * Run from functions/: node scripts/seed-pricing-config.js
 *
 * Requires: gcloud auth application-default login (or GOOGLE_APPLICATION_CREDENTIALS)
 */

const admin = require("firebase-admin");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "memoirai-7db06";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

const defaultPricing = {
  kidsBook: {
    luluPodPackageId: "1100X0850FCSTDCW080CW444MXX",
    /** Minimum retail per copy (cents). Floors thin books vs Lulu+margin. */
    basePriceCents: 2999,
    currency: "usd",
    /** Markup % on Lulu line make cost (page-count sensitive). E.g. 35 => ×1.35 on Lulu cost. */
    marginPercent: 30,
    description: "11x8.5 Hardcover Kids Book, Full Color, Matte"
  },
  standardBook: {
    luluPodPackageId: "0850X1100FCSTDCW080CW444MXX",
    basePriceCents: 2999,
    currency: "usd",
    marginPercent: 30,
    description: "8.5x11 Hardcover Portrait Book, Full Color, Matte"
  }
};

async function main() {
  try {
    await db.collection("config").doc("pricing").set(defaultPricing, { merge: true });
    console.log("\n✅ config/pricing seeded successfully.\n");
    console.log(JSON.stringify(defaultPricing, null, 2));
  } catch (err) {
    console.error("\n❌ Failed:", err.message);
    process.exit(1);
  }
}

main();
