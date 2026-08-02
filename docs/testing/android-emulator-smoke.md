# Android Emulator Smoke Test

Date: 2026-08-03

## Environment

- Flutter 3.44.8 stable, Dart 3.12.2
- JDK 17.0.16
- Android SDK 36.0.0
- Android Emulator 37.1.11
- AVD `QuoteWords_API_36`, Android 16 ARM64 Google ATD image

## Verified flow

1. `flutter doctor -v` recognized the Android SDK, JDK, emulator, and accepted licenses.
2. `flutter build apk --debug` produced a valid APK.
3. `adb install -r` installed the APK successfully.
4. Android notification permission was granted and the 09:00 repeating schedule was stored.
5. The default word-study page rendered without a process or Activity crash.
6. A slow first ISDC request timed out and correctly selected the built-in catalog.
7. The 296 x 152 card preview rendered `deposit`, then selecting `熟练` persisted progress and advanced to `allocate`.
8. The process remained foreground and no application crash appeared in logcat.

The pre-rename APK used package `tech.undef.quoteimage`. After the product identity change, `apkanalyzer` verified that the new APK uses `tech.undef.quotewords` and version `1.0.0`; the full Flutter suite, analyzer, and APK build passed again.

## Commands

```sh
flutter test
flutter analyze
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n tech.undef.quotewords/.MainActivity
adb shell pidof tech.undef.quotewords
```

## Remaining device-only checks

- Real notification delivery at 09:00
- Nearby-device runtime permission on a physical phone
- Quote/0 discovery and four-digit pairing
- Brotli decode after a complete live ISDC download
- BLE frame upload and physical e-paper refresh
