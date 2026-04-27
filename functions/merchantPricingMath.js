"use strict";

/**
 * Clamp print quantity to the same bounds as Cloud Functions ordering (1–99).
 * @param {unknown} q
 * @returns {number}
 */
function clampPrintQuantityForPricing(q) {
  const n = parseInt(String(q), 10);
  if (!Number.isFinite(n)) {
    return 1;
  }
  return Math.min(99, Math.max(1, n));
}

/**
 * Merchant retail for one cart line from Lulu's line-item make cost for that line
 * (Lulu `total_cost_incl_tax` for the line item already reflects `quantity`).
 *
 * @param {object} opts
 * @param {number} opts.luluMakeLineCents - Lulu make total for the line (all copies), in cents
 * @param {number} [opts.marginPercent] - Markup on Lulu cost (e.g. 30 => price = ceil(cost × 1.30))
 * @param {number} [opts.floorCentsPerUnit] - Minimum cents per single copy (`basePriceCents` in Firestore)
 * @param {number} [opts.quantity] - Number of copies (1–99)
 * @returns {{ bookBaseCents: number, pricingFloorApplied: boolean, dynamicLineCents: number, floorLineCents: number }}
 */
function computeBookBaseCentsFromLuluLineMake({
  luluMakeLineCents,
  marginPercent = 30,
  floorCentsPerUnit = 2999,
  quantity = 1
}) {
  const qty = clampPrintQuantityForPricing(quantity);
  const marginPct = Number.isFinite(Number(marginPercent)) ? Number(marginPercent) : 30;
  const marginMultiplier = 1 + marginPct / 100;
  const floor = Number.isFinite(Number(floorCentsPerUnit)) && floorCentsPerUnit > 0
    ? Math.round(Number(floorCentsPerUnit))
    : 2999;
  const make = Math.max(0, Math.round(Number(luluMakeLineCents) || 0));
  const dynamicLineCents = Math.ceil(make * marginMultiplier);
  const floorLineCents = floor * qty;
  const bookBaseCents = Math.max(floorLineCents, dynamicLineCents);
  const pricingFloorApplied = dynamicLineCents < floorLineCents;
  return { bookBaseCents, pricingFloorApplied, dynamicLineCents, floorLineCents };
}

module.exports = {
  clampPrintQuantityForPricing,
  computeBookBaseCentsFromLuluLineMake
};
