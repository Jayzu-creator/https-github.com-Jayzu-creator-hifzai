# HifzAI

HifzAI is a Quran reading and memorisation companion built with Flutter.

## Features

- Complete 114-Surah, 6,236-ayah Uthmani Quran bundled for offline reading
- Surah browsing and a self-guided memorisation test
- Bilingual English/Arabic interface and Tajweed learning guide
- Email/password accounts with Supabase Auth
- Consent-based short recitation recording and approximate transcript comparison
- Server-side plan periods and recitation usage quotas

The memorisation quiz asks learners to choose the next ayah from four choices,
using the complete Quran text stored in the app. The recitation tool compares an
Arabic speech transcript with the selected ayah. It is an estimate, not a Tajweed
assessment or religious ruling. Payment checkout is currently disabled. Yoco
charges are one-time: paid access lasts one or twelve calendar months and does not
renew automatically.

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

Build the web app with the Supabase project URL and public anon key:

```powershell
flutter build web --release `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key `
  --dart-define=PAYMENTS_API_BASE_URL=https://your-server.onrender.com `
  --dart-define=ENABLE_PAID_CHECKOUT=true
```

The backend defines R199 for one month of Plus, R1,499 for twelve months of Plus,
and R299 for one month of Pro. `ENABLE_PAID_CHECKOUT=true` only adds the client-side
purchase buttons; checkout still requires `PAID_PLANS_ENABLED=true` on Render.
Keep both `PAID_PLANS_ENABLED` and `RECITATION_ENABLED` disabled until the schema,
test checkout flow, provider settings, and full release have been verified. A
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
