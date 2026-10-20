const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

// Source integration checks only. Live attribution requires an eligible App Store install.
const root = resolve(__dirname, '../..');
const app = readFileSync(resolve(root, 'MemoirAI/MemoirAIApp.swift'), 'utf8');
const manager = readFileSync(resolve(root, 'MemoirAI/Paywall/SubscriptionManager.swift'), 'utf8');
const collection = 'Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()';

test('Apple Ads collection starts immediately after RevenueCat configuration', () => {
  assert.match(app, /Purchases\.configure\(withAPIKey: apiKey, appUserID: uuid\)\s*(?:\/\/[^\n]*\n\s*)?Purchases\.shared\.attribution\.enableAdServicesAttributionTokenCollection\(\)/);
  assert.equal(app.split(collection).length - 1, 1);
});

test('both verified identity paths attach attribution after applying customer info', () => {
  const identify = manager.slice(manager.indexOf('func identify(firebaseUserID:'), manager.indexOf('func refreshCustomerInfo('));
  assert.equal(identify.split(collection).length - 1, 2);
  for (const expression of ['info', 'result.customerInfo']) {
    const apply = `_ = try applyPurchaseResult(${expression}, for: firebaseUserID)`;
    const applyIndex = identify.indexOf(apply);
    assert.ok(applyIndex > 0);
    const guardIndex = identify.lastIndexOf('guard RevenueCatIdentityPolicy.canApplyCustomerInfo(', applyIndex);
    assert.ok(guardIndex >= 0, 'identity must be validated before attribution');
    const afterApply = identify.slice(applyIndex + apply.length);
    assert.match(afterApply, /^\s*(?:\/\/[^\n]*\n\s*)?Purchases\.shared\.attribution\.enableAdServicesAttributionTokenCollection\(\)/);
    assert.ok(identify.slice(guardIndex, applyIndex).includes(') else { return false }'));
  }
  assert.doesNotMatch(identify, /ATTrackingManager|trackingAuthorizationStatus|requestTrackingAuthorization/);
});
