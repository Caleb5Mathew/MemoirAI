#!/usr/bin/env node
/**
 * Validates `functions/style/bookStyles.json` (single server-side source for Gemini style paragraphs).
 * Run from CI or before deploy: `npm run check-style-sync`
 *
 * iOS `ArtStyle.memoryIllustrationStyleDescription` should stay aligned with this file for client-side
 * generation paths (covers / edits). Manual spot-check when editing either side.
 */
const fs = require("fs");
const path = require("path");

const jsonPath = path.join(__dirname, "..", "style", "bookStyles.json");
const raw = fs.readFileSync(jsonPath, "utf8");
const j = JSON.parse(raw);
const keys = ["kidsBook", "realistic", "comic", "customTemplate"];

for (const k of keys) {
  const v = j[k];
  if (typeof v !== "string" || v.trim().length < 20) {
    console.error(`check-style-sync: invalid or missing style "${k}" in ${jsonPath}`);
    process.exit(1);
  }
}

console.log(`check-style-sync: OK — ${keys.length} styles in bookStyles.json`);
