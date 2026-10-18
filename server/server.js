import http from 'node:http';
import crypto from 'node:crypto';

const port = Number(process.env.PORT || 3000);
const yocoSecretKey = process.env.YOCO_SECRET_KEY;
const appBaseUrl = process.env.APP_BASE_URL;
const allowedOrigin = process.env.ALLOWED_ORIGIN;
const paidPlansEnabled = process.env.PAID_PLANS_ENABLED === 'true';
const supabaseUrl = process.env.SUPABASE_URL?.replace(/\/+$/, '');
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const openAiApiKey = process.env.OPENAI_API_KEY;
const recitationEnabled = process.env.RECITATION_ENABLED === 'true';
const checkoutRequests = new Map();
const recitationRequests = new Map();

const products = Object.freeze({
  monthly_400: {
    amount: 19900,
    name: 'HifzAI Monthly 400',
    kind: 'subscription',
    plan: 'plus',
    months: 1,
    monthlyLimit: 400,
  },
  monthly_700: {
    amount: 29900,
    name: 'HifzAI Monthly 700',
    kind: 'subscription',
    plan: 'plus',
    months: 1,
    monthlyLimit: 700,
  },
  monthly_1000: {
    amount: 39900,
    name: 'HifzAI Monthly 1000',
    kind: 'subscription',
    plan: 'plus',
    months: 1,
    monthlyLimit: 1000,
  },
  daily_50: {
    amount: 3999,
    name: 'HifzAI 50 Recitation Pack',
    kind: 'daily_pack',
    checks: 50,
  },
  daily_100: {
    amount: 8999,
    name: 'HifzAI 100 Recitation Pack',
    kind: 'daily_pack',
    checks: 100,
  },
});

const historicalProducts = Object.freeze({
  plus_monthly: {
    amount: 19900,
    name: 'HifzAI Plus Monthly',
    kind: 'subscription',
    plan: 'plus',
    months: 1,
    monthlyLimit: 50,
  },
  plus_yearly: {
    amount: 149900,
    name: 'HifzAI Plus Yearly',
    kind: 'subscription',
    plan: 'plus',
    months: 12,
    monthlyLimit: 50,
  },
  pro_monthly: {
    amount: 29900,
    name: 'HifzAI Pro Monthly',
    kind: 'subscription',
    plan: 'pro',
    months: 1,
    monthlyLimit: 150,
  },
});

function json(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(body));
}

function cors(res, origin) {
  if (allowedOrigin && origin === allowedOrigin) {
    res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
}

function isLimited(store, key, limit, windowMs) {
  const now = Date.now();
  if (store.size > 10000) {
    for (const [storedKey, times] of store) {
      if (!times.some((time) => now - time < windowMs)) store.delete(storedKey);
    }
  }
  const recent = (store.get(key) || []).filter((time) => now - time < windowMs);
  if (recent.length >= limit) {
    store.set(key, recent);
    return true;
  }
  recent.push(now);
  store.set(key, recent);
  return false;
}

async function readJson(req) {
  let body = '';
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 10_000) throw new Error('Request body is too large.');
  }
  return body ? JSON.parse(body) : {};
}

async function readRaw(req, maxBytes) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBytes) {
      const error = new Error('Audio request exceeds the 10 MB limit.');
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

function serviceConfigured() {
  return Boolean(supabaseUrl && supabaseAnonKey && supabaseServiceRoleKey);
}

function checkoutConfigured() {
  return Boolean(
    paidPlansEnabled &&
    yocoSecretKey &&
    appBaseUrl &&
    allowedOrigin &&
    serviceConfigured(),
  );
}

async function requireUser(req) {
  const authorization = req.headers.authorization || '';
  const match = authorization.match(/^Bearer ([\w.-]+)$/);
  if (!match || !serviceConfigured()) return null;

  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      apikey: supabaseAnonKey,
      Authorization: `Bearer ${match[1]}`,
    },
  });
  if (!response.ok) return null;
  const user = await response.json();
  return typeof user.id === 'string' ? user : null;
}

async function supabaseRequest(path, options = {}) {
  if (!serviceConfigured()) throw new Error('Account service is not configured.');
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    ...options,
    headers: {
      apikey: supabaseServiceRoleKey,
      Authorization: `Bearer ${supabaseServiceRoleKey}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const payload = await response.text();
  if (!response.ok) {
    console.error(`Supabase returned HTTP ${response.status}: ${payload.slice(0, 500)}`);
    throw new Error('Account data could not be loaded.');
  }
  return payload ? JSON.parse(payload) : null;
}

async function getSubscription(userId) {
  const rows = await supabaseRequest(
    `subscriptions?user_id=eq.${encodeURIComponent(userId)}&select=plan,starts_at,expires_at`,
  );
  const row = rows?.[0];
  if (!row || Date.parse(row.expires_at) <= Date.now()) {
    return { plan: 'free', active: false, expiresAt: null };
  }
  return {
    plan: row.plan,
    active: true,
    startsAt: row.starts_at,
    expiresAt: row.expires_at,
  };
}

async function getCurrentBillingPeriod(userId, subscription) {
  if (!subscription.active) {
    return {
      monthlyLimit: 5,
      periodStart: '1970-01-01T00:00:00.000Z',
      periodEnd: null,
      isFree: true,
    };
  }

  const now = new Date().toISOString();
  const rows = await supabaseRequest(
    `subscription_payments?user_id=eq.${encodeURIComponent(userId)}&starts_at=lte.${encodeURIComponent(now)}&expires_at=gt.${encodeURIComponent(now)}&select=plan,monthly_recitations,starts_at,expires_at&order=starts_at.desc&limit=1`,
  );
  const period = rows?.[0];
  if (!period) {
    throw new Error('The active paid access period could not be found.');
  }

  const legacyLimit = period.plan === 'pro' ? 150 : 50;
  const monthlyLimit = period.monthly_recitations || legacyLimit;
  const hasNewMonthlyLimit = period.monthly_recitations > 0;
  const nowDate = new Date();
  const legacyPeriodStart = new Date(Date.UTC(
    nowDate.getUTCFullYear(),
    nowDate.getUTCMonth(),
    1,
  )).toISOString();
  const legacyPeriodEnd = new Date(Date.UTC(
    nowDate.getUTCFullYear(),
    nowDate.getUTCMonth() + 1,
    1,
  )).toISOString();

  return {
    monthlyLimit,
    periodStart: hasNewMonthlyLimit ? period.starts_at : legacyPeriodStart,
    periodEnd: hasNewMonthlyLimit ? period.expires_at : legacyPeriodEnd,
    isFree: false,
  };
}

async function getRecitationStatus(userId, billingPeriod) {
  const result = await supabaseRequest('rpc/get_recitation_status', {
    method: 'POST',
    body: JSON.stringify({
      p_user_id: userId,
      p_period_start: billingPeriod.periodStart,
      p_period_end: billingPeriod.periodEnd,
      p_is_free: billingPeriod.isFree,
    }),
  });
  return Array.isArray(result) ? result[0] : result;
}

async function getUserEntitlement(userId) {
  const subscription = await getSubscription(userId);
  const billingPeriod = await getCurrentBillingPeriod(userId, subscription);
  const usage = await getRecitationStatus(userId, billingPeriod);
  const used = usage?.used ?? billingPeriod.monthlyLimit;
  const packRemaining = usage?.pack_remaining ?? 0;
  return {
    ...subscription,
    recitationLimit: billingPeriod.monthlyLimit,
    recitationsUsed: used,
    recitationsRemaining: Math.max(0, billingPeriod.monthlyLimit - used),
    dailyPackRemaining: packRemaining,
    dailyPackExpiresAt: usage?.pack_expires_at ?? null,
    canBuyDailyPacks:
      subscription.active && used >= billingPeriod.monthlyLimit,
  };
}

async function activateVerifiedCheckout(purchase, userId) {
  const product = products[purchase.plan] || historicalProducts[purchase.plan];
  if (!product || purchase.user_id !== userId || purchase.amount !== product.amount) {
    throw new Error('Pending checkout data does not match a configured plan.');
  }
  const checkout = await yocoRequest(`/checkouts/${encodeURIComponent(purchase.checkout_id)}`);
  if (
    checkout.status !== 'completed' ||
    checkout.amount !== product.amount ||
    checkout.currency !== 'ZAR' ||
    !checkout.paymentId
  ) {
    return { checkout, entitlement: null };
  }
  const activation = product.kind === 'daily_pack'
    ? {
        endpoint: 'rpc/activate_yoco_recitation_pack',
        body: {
          p_checkout_id: checkout.id,
          p_user_id: userId,
          p_checks: product.checks,
          p_amount: product.amount,
        },
      }
    : {
        endpoint: 'rpc/activate_yoco_subscription',
        body: {
          p_checkout_id: checkout.id,
          p_user_id: userId,
          p_plan: product.plan,
          p_amount: product.amount,
          p_months: product.months,
          p_monthly_recitations: product.monthlyLimit,
        },
      };
  const result = await supabaseRequest(activation.endpoint, {
    method: 'POST',
    body: JSON.stringify(activation.body),
  });
  return {
    checkout,
    entitlement: Array.isArray(result) ? result[0] : result,
  };
}

async function reconcileRecentCheckouts(userId) {
  if (!yocoSecretKey) return;
  const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const pending = await supabaseRequest(
    `payment_checkouts?user_id=eq.${encodeURIComponent(userId)}&status=eq.pending&created_at=gte.${encodeURIComponent(cutoff)}&select=checkout_id,user_id,plan,amount&order=created_at.desc&limit=5`,
  );
  for (const purchase of pending || []) {
    await activateVerifiedCheckout(purchase, userId);
  }
}

function normalizeArabic(text) {
  return text
    .normalize('NFKD')
    .replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/g, '')
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/[^\u0600-\u06FF\s]/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

function compareArabicWords(reference, transcript) {
  const expected = normalizeArabic(reference);
  const spoken = normalizeArabic(transcript);
  const rows = Array.from({ length: expected.length + 1 }, () => []);
  for (let i = 0; i <= expected.length; i++) rows[i][0] = i;
  for (let j = 0; j <= spoken.length; j++) rows[0][j] = j;

  for (let i = 1; i <= expected.length; i++) {
    for (let j = 1; j <= spoken.length; j++) {
      rows[i][j] = expected[i - 1] === spoken[j - 1]
        ? rows[i - 1][j - 1]
        : Math.min(rows[i - 1][j - 1] + 1, rows[i - 1][j] + 1, rows[i][j - 1] + 1);
    }
  }
  const distance = rows[expected.length][spoken.length];
  const similarity = expected.length === 0
    ? 0
    : Math.max(0, Math.round((1 - distance / expected.length) * 100));
  return {
    referenceWords: expected.length,
    transcriptWords: spoken.length,
    estimatedSimilarityPercent: similarity,
  };
}

async function transcribeAudio(audio) {
  if (!openAiApiKey) throw new Error('Recitation service is not configured.');
  const form = new FormData();
  form.append('file', new Blob([audio], { type: 'audio/wav' }), 'recitation.wav');
  form.append('model', 'gpt-4o-mini-transcribe');
  form.append('language', 'ar');
  const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${openAiApiKey}` },
    body: form,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error(`OpenAI transcription returned HTTP ${response.status}.`);
    throw new Error('The audio could not be transcribed. Please try again.');
  }
  if (typeof payload.text !== 'string') throw new Error('The transcription response was invalid.');
  return payload.text;
}

async function fetchReferenceAyah(surahId, ayahNumber) {
  const response = await fetch(
    `https://api.alquran.cloud/v1/surah/${surahId}/quran-uthmani`,
    { headers: { Accept: 'application/json' } },
  );
  if (!response.ok) throw new Error('Quran reference text could not be loaded.');
  const result = await response.json();
  const ayahs = result?.data?.ayahs;
  const ayah = Array.isArray(ayahs)
    ? ayahs.find((item) => item.numberInSurah === ayahNumber)
    : null;
  if (result?.code !== 200 || typeof ayah?.text !== 'string') {
    throw new Error('That Quran ayah could not be found.');
  }
  return ayah.text;
}

async function yocoRequest(path, options = {}) {
  const response = await fetch(`https://payments.yoco.com/api${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${yocoSecretKey}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Yoco returned HTTP ${response.status}.`);
  }
  return data;
}

const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin;
  cors(res, origin);

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  try {
    const url = new URL(req.url, `http://${req.headers.host}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      return json(res, 200, { ok: true });
    }

    if (req.method === 'GET' && url.pathname === '/public-config') {
      if (!supabaseUrl || !supabaseAnonKey) {
        return json(res, 503, { error: 'Public sign-in configuration is not set.' });
      }
      return json(res, 200, {
        supabaseUrl,
        supabaseAnonKey,
      });
    }

    if (req.method === 'GET' && url.pathname === '/features') {
      return json(res, 200, {
        recitationEnabled: Boolean(recitationEnabled && openAiApiKey && serviceConfigured()),
        paidCheckoutEnabled: checkoutConfigured(),
      });
    }

    if (req.method === 'GET' && url.pathname === '/me/entitlement') {
      const user = await requireUser(req);
      if (!user) return json(res, 401, { error: 'Please sign in again.' });
      await reconcileRecentCheckouts(user.id);
      return json(res, 200, await getUserEntitlement(user.id));
    }

    if (req.method === 'POST' && url.pathname === '/create-checkout') {
      if (!paidPlansEnabled) {
        return json(res, 503, { error: 'Paid plans are coming soon and checkout is not available yet.' });
      }
      if (!yocoSecretKey || !appBaseUrl || !allowedOrigin || !serviceConfigured()) {
        return json(res, 503, { error: 'Payment service is not configured.' });
      }
      if (origin && origin !== allowedOrigin) {
        return json(res, 403, { error: 'This website is not allowed to start checkout.' });
      }
      const user = await requireUser(req);
      if (!user) return json(res, 401, { error: 'Please sign in before choosing a plan.' });
      if (isLimited(checkoutRequests, req.socket.remoteAddress || 'unknown', 10, 10 * 60 * 1000)) {
        return json(res, 429, { error: 'Too many checkout attempts. Please try again later.' });
      }

      const body = await readJson(req);
      const product = typeof body.plan === 'string' && Object.hasOwn(products, body.plan)
        ? products[body.plan]
        : null;
      if (!product) return json(res, 400, { error: 'Unknown payment plan.' });

      const current = await getUserEntitlement(user.id);
      if (product.kind === 'daily_pack' &&
          (!current.active || !current.canBuyDailyPacks)) {
        return json(res, 409, {
          error: 'Daily recitation packs are available after your monthly allowance is used.',
        });
      }
      const checkoutId = crypto.randomUUID();
      const siteUrl = appBaseUrl.replace(/\/+$/, '');
      const checkout = await yocoRequest('/checkouts', {
        method: 'POST',
        headers: { 'Idempotency-Key': checkoutId },
        body: JSON.stringify({
          amount: product.amount,
          currency: 'ZAR',
          successUrl: `${siteUrl}/?payment=success`,
          cancelUrl: `${siteUrl}/?payment=cancelled`,
          failureUrl: `${siteUrl}/?payment=failed`,
          externalId: checkoutId,
          metadata: { plan: body.plan, user_id: user.id },
          lineItems: [{
            displayName: product.name,
            quantity: 1,
            pricingDetails: { price: product.amount },
          }],
        }),
      });

      await supabaseRequest('payment_checkouts', {
        method: 'POST',
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({
          checkout_id: checkout.id,
          user_id: user.id,
          plan: body.plan,
          amount: product.amount,
          status: 'pending',
        }),
      });

      return json(res, 200, {
        checkoutId: checkout.id,
        redirectUrl: checkout.redirectUrl,
        amount: checkout.amount,
        currency: checkout.currency,
      });
    }

    if (req.method === 'GET' && url.pathname.startsWith('/checkout/')) {
      if (!yocoSecretKey || !serviceConfigured()) {
        return json(res, 503, { error: 'Payment service is not configured.' });
      }
      const user = await requireUser(req);
      if (!user) return json(res, 401, { error: 'Please sign in again to verify payment.' });
      const checkoutId = url.pathname.replace('/checkout/', '');
      if (!/^ch_[A-Za-z0-9_-]+$/.test(checkoutId)) {
        return json(res, 400, { error: 'Invalid checkout ID.' });
      }
      const purchases = await supabaseRequest(
        `payment_checkouts?checkout_id=eq.${encodeURIComponent(checkoutId)}&select=checkout_id,user_id,plan,amount,status`,
      );
      const purchase = purchases?.[0];
      if (!purchase || purchase.user_id !== user.id) {
        return json(res, 404, { error: 'This checkout does not belong to your account.' });
      }
      const { checkout, entitlement } =
          await activateVerifiedCheckout(purchase, user.id);
      return json(res, 200, {
        checkoutId: checkout.id,
        status: checkout.status,
        amount: checkout.amount,
        currency: checkout.currency,
        paymentId: checkout.paymentId,
        entitlement,
      });
    }

    if (req.method === 'POST' && url.pathname === '/recitation/check') {
      if (!recitationEnabled || !openAiApiKey || !serviceConfigured()) {
        return json(res, 503, { error: 'Recitation checking is not available yet.' });
      }
      if (origin && origin !== allowedOrigin) {
        return json(res, 403, { error: 'This website is not allowed to upload audio.' });
      }
      const user = await requireUser(req);
      if (!user) return json(res, 401, { error: 'Please sign in before checking recitation.' });
      if (isLimited(recitationRequests, user.id, 5, 10 * 60 * 1000)) {
        return json(res, 429, { error: 'Too many recitation checks. Please wait before trying again.' });
      }

      const surahId = Number(url.searchParams.get('surahId'));
      const ayahNumber = Number(url.searchParams.get('ayahNumber'));
      if (!Number.isInteger(surahId) || surahId < 1 || surahId > 114 ||
          !Number.isInteger(ayahNumber) || ayahNumber < 1 || ayahNumber > 286) {
        return json(res, 400, { error: 'Choose a valid Surah and ayah.' });
      }
      if (!req.headers['content-type']?.startsWith('audio/wav')) {
        return json(res, 415, { error: 'Audio must be sent as a WAV recording.' });
      }

      const entitlement = await getSubscription(user.id);
      const billingPeriod = await getCurrentBillingPeriod(user.id, entitlement);
      const plan = entitlement.active ? entitlement.plan : 'free';
      const usage = await supabaseRequest('rpc/reserve_recitation_check', {
        method: 'POST',
        body: JSON.stringify({
          p_user_id: user.id,
          p_limit: billingPeriod.monthlyLimit,
          p_period_start: billingPeriod.periodStart,
          p_period_end: billingPeriod.periodEnd,
          p_is_free: billingPeriod.isFree,
        }),
      });
      const reservation = Array.isArray(usage) ? usage[0] : usage;
      if (!reservation?.accepted) {
        const canBuyDailyPacks = entitlement.active &&
          reservation?.used >= billingPeriod.monthlyLimit;
        return json(res, 429, {
          error: billingPeriod.isFree
            ? 'Your five free recitation checks have been used.'
            : canBuyDailyPacks
                ? 'Your monthly allowance is used. You can buy a 24-hour recitation pack from Your Journey.'
                : 'Your monthly recitation-check allowance has been used.',
          used: reservation?.used ?? billingPeriod.monthlyLimit,
          limit: billingPeriod.monthlyLimit,
          canBuyDailyPacks,
        });
      }

      const usageId = reservation.usage_id;
      try {
        const audio = await readRaw(req, 10 * 1024 * 1024);
        if (
          audio.length < 44 ||
          audio.subarray(0, 4).toString('ascii') !== 'RIFF' ||
          audio.subarray(8, 12).toString('ascii') !== 'WAVE'
        ) {
          const error = new Error('The recording was empty or was not a valid WAV file.');
          error.statusCode = 400;
          throw error;
        }
        const reference = await fetchReferenceAyah(surahId, ayahNumber);
        const transcript = await transcribeAudio(audio);
        const comparison = compareArabicWords(reference, transcript);
        await supabaseRequest('rpc/finish_recitation_check', {
          method: 'POST',
          body: JSON.stringify({ p_usage_id: usageId, p_status: 'completed' }),
        });
        return json(res, 200, {
          transcript,
          reference,
          comparison,
          checksUsed: reservation.used,
          checksLimit: billingPeriod.monthlyLimit,
          allowanceSource: reservation.source,
          dailyPackRemaining: reservation.pack_remaining ?? 0,
          plan,
          disclaimer: 'Automated speech transcription can be inaccurate. This is not a Tajweed grade or a religious ruling. Ask a qualified Quran teacher to review your recitation.',
        });
      } catch (error) {
        if (usageId) {
          await supabaseRequest('rpc/finish_recitation_check', {
            method: 'POST',
            body: JSON.stringify({ p_usage_id: usageId, p_status: 'failed' }),
          }).catch((usageError) => console.error(usageError));
        }
        throw error;
      }
    }

    return json(res, 404, { error: 'Not found.' });
  } catch (error) {
    console.error(error);
    return json(res, error.statusCode || 500, {
      error: error.statusCode ? error.message : 'The request could not be completed.',
    });
  }
});

server.listen(port, () => console.log(`HifzAI payment server listening on port ${port}`));
