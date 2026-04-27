"use strict";

const assert = require("assert");
const { computeBookBaseCentsFromLuluLineMake } = require("./merchantPricingMath");

// Thin book: Lulu make $10 → with 30% margin = $13; floor $29.99 wins
{
  const r = computeBookBaseCentsFromLuluLineMake({
    luluMakeLineCents: 1000,
    marginPercent: 30,
    floorCentsPerUnit: 2999,
    quantity: 1
  });
  assert.strictEqual(r.bookBaseCents, 2999);
  assert.strictEqual(r.pricingFloorApplied, true);
  assert.strictEqual(r.dynamicLineCents, 1300);
  assert.strictEqual(r.floorLineCents, 2999);
}

// Thick book: Lulu make $25 → 30% = $32.50 → ceil $3250 beats floor
{
  const r = computeBookBaseCentsFromLuluLineMake({
    luluMakeLineCents: 2500,
    marginPercent: 30,
    floorCentsPerUnit: 2999,
    quantity: 1
  });
  assert.strictEqual(r.bookBaseCents, 3250);
  assert.strictEqual(r.pricingFloorApplied, false);
}

// Quantity 2: floor 2999×2 = 5998; Lulu line $20 total → 30% = $26 → floor wins
{
  const r = computeBookBaseCentsFromLuluLineMake({
    luluMakeLineCents: 2000,
    marginPercent: 30,
    floorCentsPerUnit: 2999,
    quantity: 2
  });
  assert.strictEqual(r.floorLineCents, 5998);
  assert.strictEqual(r.dynamicLineCents, 2600);
  assert.strictEqual(r.bookBaseCents, 5998);
  assert.strictEqual(r.pricingFloorApplied, true);
}

// Quantity 2: Lulu line $5000 → 30% = $6500 > floor 5998
{
  const r = computeBookBaseCentsFromLuluLineMake({
    luluMakeLineCents: 5000,
    marginPercent: 30,
    floorCentsPerUnit: 2999,
    quantity: 2
  });
  assert.strictEqual(r.bookBaseCents, 6500);
  assert.strictEqual(r.pricingFloorApplied, false);
}

console.log("merchantPricingMath.test.js: OK");
