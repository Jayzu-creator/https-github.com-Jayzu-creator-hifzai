# HifzAI

HifzAI is a free, Wi-Fi-only Quran reading and memorisation companion built with Flutter.

## Current features

- Live Uthmani Quran text loaded from the AlQuran Cloud API
- Surah browsing and readable Arabic ayahs
- Daily ayah prompt
- Tajweed learning guide
- Wi-Fi-only network access
- No account required for core Quran reading

AI recitation analysis, saved progress tracking, automatic monthly renewals, and paid features are not enabled. The plan cards clearly mark future features as planned and unavailable to buy. No test or live payments should be accepted until those services are implemented.

## Support

Email: hifzalbusinesss@gmail.com

## Privacy policy

The privacy policy draft is in [PRIVACY_POLICY.md](PRIVACY_POLICY.md). Before publishing to an app store, publish it at a public HTTPS URL.

## Running locally

Install Flutter, then run:

```bash
flutter pub get
flutter run
```

## Secure payments

The Yoco integration uses the separate Node server in [`server/`](server/README.md).
The Yoco secret key must be stored only as a server environment variable, never in
Flutter, the browser, or GitHub. Deploy the server to Render using [`render.yaml`](render.yaml),
then build the app with the public server URL:

```powershell
flutter build web --release --dart-define=PAYMENTS_API_BASE_URL=https://your-server.onrender.com
```

The backend contains the proposed Plus prices (R199 monthly, R1,499 yearly) and Pro price
(R299 monthly). Paid checkout creation is disabled unless `PAID_PLANS_ENABLED=true` is
set. Keep this disabled until the paid features, recurring-billing behavior, and access
entitlements are implemented and verified. A success redirect alone is never proof of payment.

Build a web release:

```bash
flutter build web --release
```

Build an Android App Bundle:

```bash
flutter build appbundle --release
```

## Quran text service

Quran text is requested from:

`https://api.alquran.cloud`

The service's terms and attribution requirements should be reviewed before production distribution.

## License

The application source code is licensed under the MIT License. See [LICENSE](LICENSE).
