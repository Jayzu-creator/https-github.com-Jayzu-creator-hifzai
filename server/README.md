# HifzAI payment server

This small Node server keeps the Yoco secret key off the Flutter app and browser.

## Local setup

```powershell
cd server
Copy-Item .env.example .env
```

Set the values in `.env` or in your hosting provider's environment settings. Never commit `.env`.

```powershell
$env:YOCO_SECRET_KEY = "your_yoco_test_secret"
$env:APP_BASE_URL = "http://localhost:8081"
$env:ALLOWED_ORIGIN = "http://localhost:8081"
npm start
```

## Deploying

Deploy the `server` directory to Render as a Node web service. Add `YOCO_SECRET_KEY`,
`APP_BASE_URL`, and `ALLOWED_ORIGIN` as Render environment variables. Render provides
HTTPS automatically. Keep paid checkout disabled until the plan features, payment access
entitlements, and applicable recurring billing have been implemented and verified.

The server validates the proposed plan amounts itself:

- `plus_monthly`: R199 (19,900 cents)
- `plus_yearly`: R1,499 (149,900 cents)
- `pro_monthly`: R299 (29,900 cents)

Checkout creation is disabled unless `PAID_PLANS_ENABLED=true` is set. Leave it unset
until the paid features are live. The current checkout API creates one-time payments;
it does not automatically renew monthly plans.

Yoco test transactions do not appear in the merchant dashboard or sales report. Use
Yoco's test checkout details to exercise the redirect and query `/checkout/:id` to
verify the test transaction status.
