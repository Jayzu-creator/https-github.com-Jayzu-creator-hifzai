# HifzAI account, recitation, and payment server

The Node server verifies Supabase users, serves subscription entitlements, and can
transcribe a consented short recitation. Yoco and OpenAI credentials stay on the
server; never put them in Flutter, the browser, or source control.

## Supabase setup

1. Create a Supabase project and enable email/password authentication.
2. In the SQL Editor, run [`../supabase/schema.sql`](../supabase/schema.sql).
   For an existing project, rerun the updated schema before deploying these
   monthly allowances and add-on packs.
3. In **Authentication → URL Configuration**, set the Site URL to the deployed
   app URL and add that URL to Redirect URLs. The sign-in screen can resend a
   pending signup confirmation: enter the account email and select **Resend
   confirmation email**.
4. The unauthenticated `/public-config` endpoint returns only the Supabase project
   URL and public anon key so the web app can initialize sign-in. Never return or
   bundle the service-role key; it must only be stored in Render.

The schema stores payment checkouts, paid access periods, per-period recitation
usage, 24-hour add-on packs, and a user-owned progress table. The backend grants access only after it
fetches a completed Yoco checkout and checks its amount and currency. Granting is
idempotent. All Yoco purchases are one-time charges. Monthly access lasts one month
from its access-period start and must be renewed manually; it does not auto-renew.
The 50- and 100-check add-on packs are available after the monthly allowance is
used and expire 24 hours after verified payment.
Customers may hold multiple active packs; remaining checks are combined and packs
are consumed in earliest-expiry order.

## Render configuration

Deploy `server/` as a Node web service and set:

- `YOCO_SECRET_KEY`: Yoco test or live secret (server only)
- `APP_BASE_URL`: exact public app URL
- `ALLOWED_ORIGIN`: exact origin, without a trailing slash
- `SUPABASE_URL`: project URL
- `SUPABASE_ANON_KEY`: project anon/public key
- `SUPABASE_SERVICE_ROLE_KEY`: server-only service-role key
- `OPENAI_API_KEY`: server-only OpenAI API key
- `RECITATION_ENABLED`: the Render blueprint enables consent-based testing as
  requested. Each submitted clip is forwarded to OpenAI and may incur API charges;
  disable this flag if you do not want test usage.
- `PAID_PLANS_ENABLED`: the Render blueprint enables this for the user-confirmed
  Yoco test-key setup. Use only the test secret during checkout verification;
  disable the flag until live payment and support procedures are separately approved.

Audio is kept in memory by this server and not written to disk or a database. A
consented WAV is forwarded to OpenAI for transcription. The feature compares the
transcript with the selected ayah as a rough word-similarity estimate. It does not
grade Tajweed, confirm correct pronunciation, or replace a qualified Quran teacher.
Free accounts receive five checks total. Paid monthly plans include 400, 700, or
1,000 checks for each paid month; unused monthly checks do not roll over. All paid
plans include revision recommendations, per-Surah accuracy reports, and focused
revision sessions based on saved self-graded quiz results. These study tools do not
make claims about Tajweed or pronunciation accuracy.

## Local setup

```powershell
cd server
Copy-Item .env.example .env
```

Set the environment values locally, then run `npm start`. Do not commit `.env`.

The server's fixed one-time checkout prices are:

- `monthly_400`: R199,00 for one month and 400 recitation checks
- `monthly_700`: R299,00 for one month and 700 recitation checks
- `monthly_1000`: R399,00 for one month and 1,000 recitation checks
- `daily_50`: R39,99 for 50 additional checks, valid 24 hours after payment
- `daily_100`: R89,99 for 100 additional checks, valid 24 hours after payment

`PAID_PLANS_ENABLED` defaults to disabled. Test Yoco transactions may not appear in
the merchant sales dashboard; verify their status via the authenticated
`/checkout/:id` endpoint.
