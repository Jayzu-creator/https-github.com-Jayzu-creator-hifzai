import crypto from 'node:crypto';

export const googlePlayPackageName = 'com.hifzai.quran';

export const googlePlayProducts = Object.freeze({
  monthly_400: {
    productId: 'monthly_400',
    kind: 'subscription',
    plan: 'plus',
    monthlyLimit: 400,
  },
  monthly_700: {
    productId: 'monthly_700',
    kind: 'subscription',
    plan: 'plus',
    monthlyLimit: 700,
  },
  monthly_1000: {
    productId: 'monthly_1000',
    kind: 'subscription',
    plan: 'plus',
    monthlyLimit: 1000,
  },
  daily_50: {
    productId: 'daily_50',
    kind: 'daily_pack',
    checks: 50,
  },
  daily_100: {
    productId: 'daily_100',
    kind: 'daily_pack',
    checks: 100,
  },
});

export const activeSubscriptionStates = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_CANCELED',
]);

export function purchaseTokenHash(purchaseToken) {
  return crypto.createHash('sha256').update(purchaseToken).digest('hex');
}

export function obfuscatedAccountId(userId) {
  return crypto.createHash('sha256').update(userId).digest('hex');
}

export function encryptPurchaseToken(purchaseToken, encodedKey) {
  const key = Buffer.from(encodedKey || '', 'base64');
  if (key.length !== 32) {
    throw new Error('Google Play token encryption key must be 32 bytes, base64 encoded.');
  }
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(purchaseToken, 'utf8'),
    cipher.final(),
  ]);
  return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64');
}

export function decryptPurchaseToken(encryptedToken, encodedKey) {
  const key = Buffer.from(encodedKey || '', 'base64');
  const payload = Buffer.from(encryptedToken, 'base64');
  if (key.length !== 32 || payload.length <= 28) {
    throw new Error('Google Play token encryption configuration is invalid.');
  }
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, payload.subarray(0, 12));
  decipher.setAuthTag(payload.subarray(12, 28));
  return Buffer.concat([
    decipher.update(payload.subarray(28)),
    decipher.final(),
  ]).toString('utf8');
}

export function subscriptionDisposition(subscriptionState, expiryTime, now = Date.now()) {
  const expiry = Date.parse(expiryTime || '');
  const active = activeSubscriptionStates.has(subscriptionState) &&
    Number.isFinite(expiry) && expiry > now;
  return {
    active,
    revoked: !active,
    expiresAt: Number.isFinite(expiry) ? new Date(expiry).toISOString() : null,
  };
}

let authClientPromise;

function serviceAccountCredentials() {
  if (!process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) return null;
  try {
    const credentials = JSON.parse(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON);
    if (typeof credentials.client_email !== 'string' ||
        typeof credentials.private_key !== 'string') return null;
    return credentials;
  } catch {
    return null;
  }
}

export function googlePlayConfigured() {
  return Boolean(
    process.env.GOOGLE_PLAY_PACKAGE_NAME === googlePlayPackageName &&
    serviceAccountCredentials() &&
    Buffer.from(process.env.GOOGLE_PLAY_TOKEN_ENCRYPTION_KEY || '', 'base64').length === 32,
  );
}

async function getAuthClient() {
  if (!googlePlayConfigured()) throw new Error('Google Play verification is not configured.');
  authClientPromise ??= (async () => {
    const { GoogleAuth } = await import('google-auth-library');
    return new GoogleAuth({
      credentials: serviceAccountCredentials(),
      scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    }).getClient();
  })();
  return authClientPromise;
}

export async function googlePlayApi(path, options = {}) {
  const client = await getAuthClient();
  const { token } = await client.getAccessToken();
  if (!token) throw new Error('Google Play service authentication failed.');
  const response = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(process.env.GOOGLE_PLAY_PACKAGE_NAME)}${path}`,
    {
      ...options,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      },
    },
  );
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(`Google Play Developer API returned HTTP ${response.status}.`);
    error.statusCode = response.status;
    throw error;
  }
  return payload;
}

export async function verifyRtdnAuthorization(req) {
  const audience = process.env.GOOGLE_PLAY_RTDN_AUDIENCE;
  const expectedEmail = process.env.GOOGLE_PLAY_RTDN_EMAIL;
  if (!audience || !expectedEmail) return false;
  const authorization = req.headers.authorization || '';
  const match = authorization.match(/^Bearer ([A-Za-z0-9._-]+)$/);
  if (!match) return false;
  try {
    const { OAuth2Client } = await import('google-auth-library');
    const ticket = await new OAuth2Client().verifyIdToken({
      idToken: match[1],
      audience,
    });
    const payload = ticket.getPayload();
    return payload?.email_verified === true &&
      payload.email === expectedEmail;
  } catch {
    return false;
  }
}
