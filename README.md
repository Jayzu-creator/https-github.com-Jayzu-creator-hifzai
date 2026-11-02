# HifzAI

HifzAI is a Quran reading and memorisation companion built with Flutter.

## Features

- Complete 114-Surah, 6,236-ayah Uthmani Quran bundled for offline reading
- Surah browsing and a self-guided memorisation test
- Bilingual English/Arabic interface and Tajweed learning guide
- Email/password accounts with Supabase Auth
- Consent-based short recitation recording and approximate transcript comparison
- Server-enforced lifetime free allowance, monthly plan limits, and 24-hour add-on packs
- Android auto-renewing subscriptions through Google Play Billing; Yoco checkout is website-only
- Paid revision recommendations, per-Surah accuracy reports, and focused revision quizzes

The memorisation quiz asks learners to choose the next ayah from four choices,
using the complete Quran text stored in the app. The recitation tool compares an
Arabic speech transcript with the selected ayah. It is an estimate, not a Tajweed
assessment or religious ruling. Free accounts receive five recitation checks total.
Paid monthly packages include 400, 700, or 1,000 checks and the same study tools.
On the website, Yoco charges each purchase once; customers manually renew monthly
access because the documented Yoco Checkout API does not provide automatic recurring
charges. Android uses monthly auto-renewing Google Play subscriptions that users
manage or cancel in Google Play. Store prices are localized by Google Play.
When a paid monthly allowance is exhausted, users can buy a 50-check pack for
R39,99 or a 100-check pack for R89,99. Each add-on pack expires 24 hours after
payment is verified; multiple active packs add together.

All paid monthly packages include personalised recommendations, per-Surah
performance reports, and focused revision quizzes based on saved quiz outcomes.
These features do not provide Tajweed or pronunciation grading. Each submitted
recording is sent to OpenAI and may incur API charges. Verify test payments,
entitlement periods, usage limits, and recording flows before any live launch.

## Support and privacy

Support: hifzalbusinesss@gmail.com

See [PRIVACY_POLICY.md](PRIVACY_POLICY.md) for account, payment, and audio-processing
details. Publish the policy at a public HTTPS URL before store release.

## Running locally

Create/configure a Supabase project as described in [`server/README.md`](server/README.md),
then run:

```powershell
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

The Supabase anon key is intended for client builds. Never expose the Supabase
service-role key, Yoco secret, or OpenAI key in Flutter, the browser, or GitHub.
Keep server keys in Render environment settings.

## Backend and production build

The separate Node server provides account entitlements, authenticated website-only
Yoco checkout and status verification, server-verified Google Play Billing for
Android, and optional recitation transcription. Run the SQL schema
in `supabase/schema.sql` in the Supabase SQL Editor, then configure Render as detailed
in [`server/README.md`](server/README.md) and [`render.yaml`](render.yaml).

For local web builds, the app can load the public Supabase configuration from the
backend. Optional `SUPABASE_URL` and `SUPABASE_ANON_KEY` defines can be supplied
when building instead:

```powershell
flutter build web --release `
  --base-href=/https-github.com-Jayzu-creator-hifzai/ `
  --dart-define=PAYMENTS_API_BASE_URL=https://your-server.onrender.com `
  --dart-define=ENABLE_PAID_CHECKOUT=true
```

GitHub Pages is deployed by [`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml)
from `main`. In repository **Settings → Pages**, set the build and deployment
source to **GitHub Actions**.

If the two Supabase build values are omitted, the app loads the public project URL
and anon key from the backend's `/public-config` endpoint. The anon key is
publishable and is protected by Supabase row-level security; the service-role key
is never returned by that endpoint.

Google Play Android uses subscription product IDs `monthly_400`, `monthly_700`,
and `monthly_1000`, plus one-time add-on product IDs `daily_50` and `daily_100`.
Configure the three monthly products as auto-renewing monthly subscriptions and
the add-ons as one-time in-app products in Play Console. The backend verifies each
purchase token with the Android Publisher API and does not trust a client-side
purchase-success callback. Google Play billing remains disabled until its service
account, token-encryption key, Supabase migration, and authenticated RTDN push
subscription are configured as described in [`server/README.md`](server/README.md).

The website backend defines one-time plans of R199,00 for 400 checks, R299,00 for 700,
and R399,00 for 1,000, plus 24-hour add-on packs of R39,99 for 50 checks and
R89,99 for 100. `ENABLE_PAID_CHECKOUT=true` only adds the client-side purchase
buttons; checkout still requires `PAID_PLANS_ENABLED=true` on Render.
The Render blueprint enables Yoco checkout only for the user-confirmed test-key
setup and enables consent-based recitation testing. Website monthly access is a
one-time charge for one month and must be renewed manually; it does not auto-renew.
Android subscriptions auto-renew through Google Play until canceled. Keep live
payment credentials disabled and do not switch to production until schema
migrations, test purchases, RTDN cancellation/refund handling, OpenAI transcription,
provider settings, and the complete release have been verified. A success redirect
or client callback alone is never proof of payment.

## Quran text and attribution

The bundled Arabic verse text uses Quran.com's Uthmani script API
(`https://api.quran.com`) and includes all 114 chapter records and 6,236 keyed
verses. It is included locally so Surah reading and the quiz work without a
Quran-text network request. Recitation comparison still requires internet access.
The server uses AlQuran Cloud as a separate live reference during recitation
comparison. Review the text providers' reuse terms and attribution requirements
before production distribution.

## License

The application source code is licensed under the MIT License. See [LICENSE](LICENSE).
