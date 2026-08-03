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
6. The built-in `deposit` card rendered immediately while the first ISDC request continued in the background.
7. The 296 x 152 preview placed phonetic and Chinese definition on one row and showed the Chinese example below English.
8. Selecting `熟练` persisted progress and advanced to `allocate`.
9. The process remained foreground and no application crash appeared in logcat.
10. Version 1.0.2+3 upgraded in place and exposed `清晰灰阶` and `锐利黑白` on the image page.

The pre-rename APK used package `tech.undef.quoteimage`. Versions 1.0.1+2 and 1.0.2+3 intentionally retain that application ID so Android secure storage remains accessible after an in-place, same-signature upgrade. The Dart/Kotlin product namespace remains `tech.undef.quotewords`.

## Commands

```sh
flutter test
flutter analyze
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n tech.undef.quoteimage/tech.undef.quotewords.MainActivity
adb shell pidof tech.undef.quoteimage
```

## Remaining device-only checks

- Real notification delivery at 09:00
- Nearby-device runtime permission on a physical phone
- Quote/0 discovery and four-digit pairing
- Recovery of an existing same-phone, same-signature pairing credential
- Brotli decode after a complete live ISDC download
- BLE frame upload and physical e-paper refresh
