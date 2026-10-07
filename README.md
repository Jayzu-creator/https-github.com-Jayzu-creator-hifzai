# HifzAI

HifzAI is a Quran reading and memorisation companion built with Flutter.

## Features

- Complete 114-Surah, 6,236-ayah Uthmani Quran bundled for offline reading
- Surah browsing and a self-guided memorisation test
- Bilingual English/Arabic interface and Tajweed learning guide
- Email/password accounts with Supabase Auth
- Consent-based short recitation recording and approximate transcript comparison
- Server-side plan periods and recitation usage quotas
- Plus revision recommendations and Pro per-Surah accuracy reports with focused revision quizzes

The memorisation quiz asks learners to choose the next ayah from four choices,
using the complete Quran text stored in the app. The recitation tool compares an
Arabic speech transcript with the selected ayah. It is an estimate, not a Tajweed
assessment or religious ruling. Payment checkout is currently disabled. Yoco
charges are one-time: paid access lasts one or twelve calendar months and does not
renew automatically. Live checkout has not yet been deployed; the backend
configuration targets Yoco test mode, not live charges.

Plus and Pro include respectively 50 and 150 estimated transcript comparisons per
UTC month when the recitation service is enabled. Plus recommendations and Pro
performance reports are based on the learner's saved quiz outcomes; focused
revision quizzes target ayahs marked for review. These features do not provide
Tajweed or pronunciation grading. The live backend currently reports paid checkout
and recitation as disabled. The deployment configuration now enables Yoco test
checkout and consent-based test recitation; it must be redeployed before the
feature flags can take effect. Each submitted recording is sent to OpenAI and may
incur API charges. Verify the test payment and recording flows before any live
launch.

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

The separate Node server provides account entitlements, authenticated Yoco checkout
and status verification, and optional recitation transcription. Run the SQL schema
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

The backend defines R199 for one month of Plus, R1,499 for twelve months of Plus,
and R299 for one month of Pro. `ENABLE_PAID_CHECKOUT=true` only adds the client-side
purchase buttons; checkout still requires `PAID_PLANS_ENABLED=true` on Render.
The Render blueprint enables checkout only for the user-confirmed Yoco test-key
setup and enables consent-based recitation testing. Keep live Yoco credentials
disabled and do not switch to production until the schema, test checkout, OpenAI
transcription, provider settings, and complete release have been verified. A
success redirect alone is never proof of payment.

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
