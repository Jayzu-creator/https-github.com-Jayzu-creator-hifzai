# HifzAI account, recitation, and payment server

The Node server verifies Supabase users, serves subscription entitlements, and can
transcribe a consented short recitation. Yoco and OpenAI credentials stay on the
server; never put them in Flutter, the browser, or source control.

## Supabase setup

1. Create a Supabase project and enable email/password authentication.
2. In the SQL Editor, run [`../supabase/schema.sql`](../supabase/schema.sql).
3. Configure the site's allowed redirect URL in Supabase Auth for account confirmation.
4. Keep the project URL, anon key, and service-role key private to their intended
   settings. The anon key is public and may be included in the Flutter build; the
   service-role key must only be stored in Render.

The schema stores payment checkouts, paid access periods, per-period recitation
usage, and a user-owned progress table. The backend grants access only after it
fetches a completed Yoco checkout and checks its amount and currency. Granting is
idempotent. Yoco purchases are one-time charges: monthly access lasts one calendar
month and yearly access lasts twelve calendar months; neither renews automatically.

## Render configuration

Deploy `server/` as a Node web service and set:

- `YOCO_SECRET_KEY`: Yoco test or live secret (server only)
- `APP_BASE_URL`: exact public app URL
- `ALLOWED_ORIGIN`: exact origin, without a trailing slash
- `SUPABASE_URL`: project URL
- `SUPABASE_ANON_KEY`: project anon/public key
- `SUPABASE_SERVICE_ROLE_KEY`: server-only service-role key
- `OPENAI_API_KEY`: server-only OpenAI API key
- `RECITATION_ENABLED`: keep `false` until provider settings, privacy disclosures,
  and an end-to-end recording test are complete
- `PAID_PLANS_ENABLED`: keep `false` until Yoco test transactions, subscription
  grants, refunds/support procedures, and the complete release are verified

Audio is kept in memory by this server and not written to disk or a database. A
consented WAV is forwarded to OpenAI for transcription. The feature compares the
transcript with the selected ayah as a rough word-similarity estimate. It does not
grade Tajweed, confirm correct pronunciation, or replace a qualified Quran teacher.
Free accounts are limited to three completed checks per UTC day; Plus and Pro
entitlements allow 50 and 150 checks per UTC month respectively.

## Local setup

```powershell
cd server
Copy-Item .env.example .env
```

Set the environment values locally, then run `npm start`. Do not commit `.env`.

The server's fixed one-time checkout prices are:

- `plus_monthly`: R199 for one calendar month
- `plus_yearly`: R1,499 for twelve calendar months
- `pro_monthly`: R299 for one calendar month

`PAID_PLANS_ENABLED` defaults to disabled. Test Yoco transactions may not appear in
the merchant sales dashboard; verify their status via the authenticated
`/checkout/:id` endpoint.
