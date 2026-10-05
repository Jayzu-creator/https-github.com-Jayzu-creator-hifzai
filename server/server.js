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

const plans = Object.freeze({
  plus_monthly: { amount: 19900, name: 'HifzAI Plus Monthly', plan: 'plus', months: 1 },
  plus_yearly: { amount: 149900, name: 'HifzAI Plus Yearly', plan: 'plus', months: 12 },
  pro_monthly: { amount: 29900, name: 'HifzAI Pro Monthly', plan: 'pro', months: 1 },
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

async function activateVerifiedCheckout(purchase, userId) {
  const plan = plans[purchase.plan];
  if (!plan || purchase.user_id !== userId || purchase.amount !== plan.amount) {
    throw new Error('Pending checkout data does not match a configured plan.');
  }
  const checkout = await yocoRequest(`/checkouts/${encodeURIComponent(purchase.checkout_id)}`);
  if (
    checkout.status !== 'completed' ||
    checkout.amount !== plan.amount ||
    checkout.currency !== 'ZAR' ||
    !checkout.paymentId
  ) {
    return { checkout, entitlement: null };
  }
  const result = await supabaseRequest('rpc/activate_yoco_subscription', {
    method: 'POST',
    body: JSON.stringify({
      p_checkout_id: checkout.id,
      p_user_id: userId,
      p_plan: plan.plan,
      p_amount: plan.amount,
      p_months: plan.months,
    }),
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
      return json(res, 200, await getSubscription(user.id));
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
      const plan = plans[body.plan];
      if (!plan) return json(res, 400, { error: 'Unknown payment plan.' });

      const current = await getSubscription(user.id);
      if (current.expiresAt && current.plan !== plan.plan) {
        return json(res, 409, {
          error: 'You already have a different paid plan active. Renew or change plans after it expires.',
        });
      }
      const checkoutId = crypto.randomUUID();
      const siteUrl = appBaseUrl.replace(/\/+$/, '');
      const checkout = await yocoRequest('/checkouts', {
        method: 'POST',
        headers: { 'Idempotency-Key': checkoutId },
        body: JSON.stringify({
          amount: plan.amount,
          currency: 'ZAR',
          successUrl: `${siteUrl}/?payment=success`,
          cancelUrl: `${siteUrl}/?payment=cancelled`,
          failureUrl: `${siteUrl}/?payment=failed`,
          externalId: checkoutId,
          metadata: { plan: body.plan, user_id: user.id },
          lineItems: [{
            displayName: plan.name,
            quantity: 1,
            pricingDetails: { price: plan.amount },
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
          amount: plan.amount,
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
      const isPaid = entitlement.expiresAt != null &&
        Date.parse(entitlement.expiresAt) > Date.now();
      const plan = isPaid ? entitlement.plan : 'free';
      const limit = plan === 'plus' ? 50 : plan === 'pro' ? 150 : 3;
      const now = new Date();
      const periodStart = plan === 'free'
        ? new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
        : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
      const usage = await supabaseRequest('rpc/reserve_recitation_check', {
        method: 'POST',
        body: JSON.stringify({
          p_user_id: user.id,
          p_limit: limit,
          p_period_start: periodStart.toISOString(),
        }),
      });
      const reservation = Array.isArray(usage) ? usage[0] : usage;
      if (!reservation?.accepted) {
        return json(res, 429, {
          error: plan === 'free'
            ? 'Your 3 free daily checks have been used. Try again tomorrow or see HifzAI plans.'
            : 'Your monthly recitation-check allowance has been used.',
          used: reservation?.used ?? limit,
          limit,
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
          checksLimit: limit,
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
