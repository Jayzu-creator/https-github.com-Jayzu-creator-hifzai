import http from 'node:http';
import crypto from 'node:crypto';

const port = Number(process.env.PORT || 3000);
const yocoSecretKey = process.env.YOCO_SECRET_KEY;
const appBaseUrl = process.env.APP_BASE_URL;
const allowedOrigin = process.env.ALLOWED_ORIGIN;
const paidPlansEnabled = process.env.PAID_PLANS_ENABLED === 'true';
const checkoutRequests = new Map();

const plans = Object.freeze({
  plus_monthly: { amount: 19900, name: 'HifzAI Plus Monthly' },
  plus_yearly: { amount: 149900, name: 'HifzAI Plus Yearly' },
  pro_monthly: { amount: 29900, name: 'HifzAI Pro Monthly' },
});

function isRateLimited(ip) {
  const now = Date.now();
  const recent = (checkoutRequests.get(ip) || []).filter((time) => now - time < 10 * 60 * 1000);
  if (recent.length >= 10) {
    checkoutRequests.set(ip, recent);
    return true;
  }
  recent.push(now);
  checkoutRequests.set(ip, recent);
  return false;
}

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
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
}

async function readJson(req) {
  let body = '';
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 10_000) throw new Error('Request body is too large.');
  }
  return body ? JSON.parse(body) : {};
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

    if (req.method === 'POST' && url.pathname === '/create-checkout') {
      if (!paidPlansEnabled) {
        return json(res, 503, { error: 'Paid plans are coming soon and checkout is not available yet.' });
      }
      if (!yocoSecretKey || !appBaseUrl || !allowedOrigin) {
        return json(res, 503, { error: 'Payment service is not configured.' });
      }
      if (origin && origin !== allowedOrigin) {
        return json(res, 403, { error: 'This website is not allowed to start checkout.' });
      }
      if (isRateLimited(req.socket.remoteAddress || 'unknown')) {
        return json(res, 429, { error: 'Too many checkout attempts. Please try again later.' });
      }

      const body = await readJson(req);
      const plan = plans[body.plan];
      if (!plan) return json(res, 400, { error: 'Unknown payment plan.' });

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
          metadata: { plan: body.plan },
          lineItems: [{
            displayName: plan.name,
            quantity: 1,
            pricingDetails: { price: plan.amount },
          }],
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
      if (!yocoSecretKey) return json(res, 503, { error: 'Payment service is not configured.' });
      const checkoutId = url.pathname.replace('/checkout/', '');
      if (!/^ch_[A-Za-z0-9_-]+$/.test(checkoutId)) {
        return json(res, 400, { error: 'Invalid checkout ID.' });
      }
      const checkout = await yocoRequest(`/checkouts/${encodeURIComponent(checkoutId)}`);
      return json(res, 200, {
        checkoutId: checkout.id,
        status: checkout.status,
        amount: checkout.amount,
        currency: checkout.currency,
        paymentId: checkout.paymentId,
      });
    }

    return json(res, 404, { error: 'Not found.' });
  } catch (error) {
    console.error(error);
    return json(res, 500, { error: 'The request could not be completed.' });
  }
});

server.listen(port, () => console.log(`HifzAI payment server listening on port ${port}`));
