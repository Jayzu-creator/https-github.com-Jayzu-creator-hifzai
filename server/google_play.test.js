import assert from 'node:assert/strict';
import test from 'node:test';

import {
  activeSubscriptionStates,
  decryptPurchaseToken,
  encryptPurchaseToken,
  googlePlayProducts,
  obfuscatedAccountId,
  purchaseTokenHash,
  subscriptionDisposition,
} from './google_play.js';

test('Google Play catalog fixes the expected product mapping', () => {
  assert.deepEqual(Object.keys(googlePlayProducts), [
    'monthly_400',
    'monthly_700',
    'monthly_1000',
    'daily_50',
    'daily_100',
  ]);
  assert.equal(googlePlayProducts.monthly_400.monthlyLimit, 400);
  assert.equal(googlePlayProducts.monthly_700.monthlyLimit, 700);
  assert.equal(googlePlayProducts.monthly_1000.monthlyLimit, 1000);
  assert.equal(googlePlayProducts.daily_50.checks, 50);
  assert.equal(googlePlayProducts.daily_100.checks, 100);
});

test('account and purchase-token hashes are deterministic and non-reversible identifiers', () => {
  const accountHash = obfuscatedAccountId('user-123');
  const tokenHash = purchaseTokenHash('sensitive-purchase-token');

  assert.match(accountHash, /^[a-f0-9]{64}$/);
  assert.match(tokenHash, /^[a-f0-9]{64}$/);
  assert.notEqual(accountHash, 'user-123');
  assert.notEqual(tokenHash, 'sensitive-purchase-token');
  assert.equal(accountHash, obfuscatedAccountId('user-123'));
});

test('purchase tokens are authenticated-encrypted for server-side renewal checks', () => {
  const key = Buffer.alloc(32, 7).toString('base64');
  const encrypted = encryptPurchaseToken('purchase-token-value', key);

  assert.notEqual(encrypted, 'purchase-token-value');
  assert.equal(decryptPurchaseToken(encrypted, key), 'purchase-token-value');
  assert.throws(() => decryptPurchaseToken(encrypted, Buffer.alloc(32, 8).toString('base64')));
  assert.throws(() => encryptPurchaseToken('token', 'not-a-key'));
});

test('subscription cancellation keeps access only through the verified expiry', () => {
  const now = Date.parse('2026-10-30T00:00:00.000Z');
  const expiry = '2026-11-30T00:00:00.000Z';

  for (const state of activeSubscriptionStates) {
    assert.deepEqual(subscriptionDisposition(state, expiry, now), {
      active: true,
      revoked: false,
      expiresAt: expiry,
    });
  }
  assert.deepEqual(
    subscriptionDisposition('SUBSCRIPTION_STATE_CANCELED', expiry, Date.parse(expiry)),
    { active: false, revoked: true, expiresAt: expiry },
  );
  assert.equal(
    subscriptionDisposition('SUBSCRIPTION_STATE_ON_HOLD', expiry, now).active,
    false,
  );
});
