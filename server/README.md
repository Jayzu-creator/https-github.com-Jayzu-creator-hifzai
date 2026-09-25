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
HTTPS automatically. Use the Yoco test key first, then replace it with the live key only
after the test checkout and status flow are verified.

The server validates plans itself:

- `monthly`: R200 (20,000 cents)
- `yearly`: R1500 (150,000 cents)

The app must not unlock paid features from the redirect URL alone. The `/checkout/:id`
status endpoint must be checked server-side before access is granted. Recurring monthly
billing also requires a Yoco-supported recurring-billing product; this checkout currently
creates a one-time payment.
