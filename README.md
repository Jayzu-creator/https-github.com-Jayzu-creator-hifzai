# HifzAI

HifzAI is a free, Wi-Fi-only Quran reading and memorisation companion built with Flutter.

## Current features

- Live Uthmani Quran text loaded from the AlQuran Cloud API
- Surah browsing and readable Arabic ayahs
- Daily ayah prompt
- Tajweed learning guide
- Wi-Fi-only network access
- No account, subscription, advertisements, or payment system

Recitation analysis is not enabled in the current release. The app does not claim to record or assess a user's voice.

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
