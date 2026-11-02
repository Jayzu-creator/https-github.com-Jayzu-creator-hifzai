# HifzAI account, recitation, and payment server

The Node server verifies Supabase users, serves subscription entitlements, verifies
Google Play purchase tokens, offers website-only Yoco checkout, and can transcribe a
consented short recitation. Payment-provider credentials stay on the server; never
put them in Flutter, the browser, or source control.

## Supabase setup

1. Create a Supabase project and enable email/password authentication.
2. In the SQL Editor, run [`../supabase/schema.sql`](../supabase/schema.sql).
   For an existing project, rerun the updated schema before deploying these
   monthly allowances and add-on packs.
3. In **Authentication → URL Configuration**, set the Site URL to the deployed
   app URL and add that URL to Redirect URLs. The sign-in screen can resend a
   pending signup confirmation or request a password reset; users should enter
   their account email and select the relevant action.
4. Configure custom SMTP under **Authentication → Emails → SMTP Settings** for
   reliable delivery to users. Supabase's default email service is restricted to
   project-team addresses and has a low sending rate limit.
5. The unauthenticated `/public-config` endpoint returns only the Supabase project
   URL and public anon key so the web app can initialize sign-in. Never return or
   bundle the service-role key; it must only be stored in Render.

The schema stores website checkouts, verified Play purchase references and renewal
orders, paid access periods, per-period recitation usage, 24-hour add-on packs, and
a user-owned progress table. Google Play access is granted only after the backend
queries the Android Publisher API with the purchase token and checks the package,
product, account binding, purchase state, and expiry. Activation is idempotent.
Yoco is used only by the website, and all Yoco purchases are one-time charges.
Website monthly access must be renewed manually; Android subscriptions auto-renew
monthly until canceled in Google Play. A cancellation retains access until the
verified expiry; expiration, hold, revocation, and voided-purchase notifications
remove access or unused add-on checks. Remaining add-on checks expire 24 hours
after verified fulfillment. A refund cannot reverse checks already consumed.

## Google Play Billing setup (Android)

The product IDs are fixed in the client and backend:

- `monthly_400`: auto-renewing monthly subscription; 400 monthly recitation checks
- `monthly_700`: auto-renewing monthly subscription; 700 monthly recitation checks
- `monthly_1000`: auto-renewing monthly subscription; 1,000 monthly recitation checks
- `daily_50`: one-time in-app product; 50 checks, expires 24 hours after fulfillment
- `daily_100`: one-time in-app product; 100 checks, expires 24 hours after fulfillment

Create the three monthly products as monthly auto-renewing plans (not prepaid
plans) and group them together in Play Console so Google Play handles plan changes
and prevents overlapping plans. Configure the IDs exactly as above. Add-on packs
must be one-time products. Google Play controls localized prices; the UI displays
the store-returned price rather than trusting a client-supplied amount. Configure
the Android application/package ID as `com.hifzai.quran`.

Before enabling billing:

1. Apply `../supabase/schema.sql` to the production Supabase project. Google Play
   purchase tables are service-role only; the app never reads purchase tokens.
2. In Google Cloud, enable the **Google Play Android Developer API**. Create a
   service account, add its email in Play Console **Users and permissions**, and
   grant the permissions needed to view purchases and manage orders/subscriptions.
   Use a dedicated account with the minimum permissions supported by Play Console.
3. Store the complete service-account JSON in Render as the secret
   `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Keep it out of Git, Flutter defines, logs,
   and client responses.
4. Generate a random 32-byte key and base64-encode it for the Render secret
   `GOOGLE_PLAY_TOKEN_ENCRYPTION_KEY`. For Windows PowerShell, generate one locally:

   ```powershell
   $bytes = New-Object byte[] 32
   [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
   [Convert]::ToBase64String($bytes)
   ```

   The backend stores only a SHA-256 token index and AES-256-GCM encrypted token
   for entitlement reconciliation and refunds. Back up the key securely; rotating
   it without re-encrypting existing rows prevents future token refresh.
5. Set `GOOGLE_PLAY_PACKAGE_NAME=com.hifzai.quran` and keep
   `GOOGLE_PLAY_BILLING_ENABLED=false` until every verification and notification
   setup step has been tested.
6. Configure Google Play **Real-time developer notifications (RTDN)** to publish
   subscription and one-time-product notifications to a Pub/Sub topic. Create an
   authenticated push subscription to
   `https://<render-service-host>/google-play/rtdn`, with a Google OIDC token.
   Set its audience to that exact URL in Render as
   `GOOGLE_PLAY_RTDN_AUDIENCE`, and set the push-auth service account email as
   `GOOGLE_PLAY_RTDN_EMAIL`. Grant Pub/Sub's service agent permission to mint tokens
   for that push-auth service account. The server requires both values and rejects
   unsigned or wrong-audience notifications.
7. Send a Pub/Sub test notification, then test purchase, renewal, user cancellation,
   expiration, refund/void, and retry scenarios with Play license testers. Only
   then set `GOOGLE_PLAY_BILLING_ENABLED=true`.

The Android client sends the Play purchase token to the authenticated backend.
The server validates the token and links it to a SHA-256 hash of the signed-in
Supabase user ID passed as Google Play's obfuscated account ID. It acknowledges
subscriptions or consumes add-ons only after atomic entitlement activation. The
client calls `completePurchase` only after that verified backend response; if
verification or provider completion fails, the transaction remains retryable.
Subscriptions are also reconciled against Google Play when entitlements are
loaded. RTDN is required for prompt cancellation, expiration, and refund/void
processing; if RTDN isn't configured and tested, keep Play billing disabled.
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
- `GOOGLE_PLAY_BILLING_ENABLED`: defaults to false. Enable only after Google Play
  verification, encrypted token storage, schema migration, and RTDN have been tested.
- `GOOGLE_PLAY_PACKAGE_NAME`: `com.hifzai.quran`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: Google Play Developer API service-account JSON (secret)
- `GOOGLE_PLAY_TOKEN_ENCRYPTION_KEY`: base64-encoded random 32-byte encryption key (secret)
- `GOOGLE_PLAY_RTDN_AUDIENCE`: exact HTTPS RTDN push endpoint URL (not a secret)
- `GOOGLE_PLAY_RTDN_EMAIL`: service account email used for authenticated Pub/Sub push

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
