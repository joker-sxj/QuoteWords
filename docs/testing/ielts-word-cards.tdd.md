# IELTS Word Cards TDD Evidence

Date: 2026-08-02

## Source and user journeys

No external plan file was used. The journeys were derived from the product
decisions agreed for the Android client:

- As an IELTS learner, I receive a 09:00 reminder and study 8 new words by
  default, with no more than the configured daily limit.
- As an e-paper user, I see one sparse, readable 296 x 152 monochrome word card
  at a time.
- As a learner, I rate recall and have the result scheduled at 10 minutes, then
  1, 3, 7, 14, and 30 days.
- As a returning learner, I resume the same daily queue and position after an
  app restart; a new day puts due reviews before new words.
- As a learner with more time, I can raise the new-word setting and continue
  studying today without losing completed progress.
- As an offline learner, I use a fresh local catalog or stale cache; only the
  first sync with no cache falls back to compact built-in cards.

## Task report

| Behavior | RED evidence | GREEN evidence | Validation |
|---|---|---|---|
| Review schedule and e-paper card layout | `448bda8` | `56c1521` | `flutter test test/review_scheduler_test.dart test/word_card_renderer_test.dart` |
| Android settings, reminder, study UI, and image-page regression | `1bf622b` | `2d6d1cb` | `flutter test test/study_settings_test.dart test/study_reminder_test.dart test/word_study_screen_test.dart` |
| Minimal ISDC extraction | `848b3f8` | `9a25a46` | `flutter test test/isdc_catalog_parser_test.dart` |
| Seven-day cache with stale fallback | `769fb8c` | `e0c7365` | `flutter test test/vocabulary_catalog_test.dart` |
| ISDC source and local catalog file adapters | `738db9f` | `b879b17` | `flutter test test/catalog_adapters_test.dart` |
| Fixed daily queue and persisted ratings | `cc6ef55` | `3d4524c` | `flutter test test/study_session_test.dart test/review_scheduler_test.dart` |
| JSON study-state persistence and corrupt-file fallback | `6465a9e` | `5efcdf3` | `flutter test test/study_state_store_test.dart test/study_session_test.dart` |
| Synchronized words rendered and ratings persisted through UI | `2c4751a` | `4c38582` | `flutter test test/word_study_screen_test.dart test/study_session_test.dart test/study_state_store_test.dart` |
| Same-day additional study | `7f76084` | `3cac17f` | `flutter test test/study_session_test.dart test/word_study_screen_test.dart test/review_scheduler_test.dart` |
| Standalone QuoteWords identity | `6321cd6` | `5ee73a7` | `flutter test test/project_identity_test.dart` |
| Hard 24-card daily ceiling | `4705ade` | `24aa1da` | `flutter test test/study_settings_test.dart` |
| Preserve credentials from previously paired Android installs | `f385476` | `ed42312` | `flutter test test/project_identity_test.dart` and APK manifest inspection |
| Immediate card while the catalog refreshes | `b0100d7` | `16a3083` | `flutter test test/vocabulary_catalog_test.dart test/word_study_screen_test.dart` |
| Parse and cache ISDC Chinese example field `ec` | `e4e7704` | `bcc1bcf` | `flutter test test/isdc_catalog_parser_test.dart test/catalog_adapters_test.dart` |
| Pass Chinese examples from study data to card rendering | `9087de8` | `d890134` | `flutter test test/word_study_screen_test.dart` |
| Compact bilingual 296 x 152 card layout | `5babd3c` | `746e6f6` | `flutter test test/word_card_renderer_test.dart` |

Each RED test failed for the intended missing type, method, or behavior before
its paired production commit. The checkpoint commits remain reachable from
the standalone repository history.

## Test specification

| # | Guarantee | Test target | Type | Result |
|---|---|---|---|---|
| 1 | Default settings are 8 new words, daily limit 24, reminder 09:00 | `study_settings_test.dart` | Unit | PASS |
| 2 | Recall ratings follow the configured Ebbinghaus intervals | `review_scheduler_test.dart` | Unit | PASS |
| 3 | Due reviews precede frequency-sorted new words | `review_scheduler_test.dart`, `study_session_test.dart` | Unit | PASS |
| 4 | A same-day restart resumes the fixed queue and index | `study_session_test.dart` | Unit | PASS |
| 5 | A new day rebuilds from due persisted progress | `study_session_test.dart` | Unit | PASS |
| 6 | Increasing new words appends cards without resetting progress | `study_session_test.dart`, `word_study_screen_test.dart` | Unit/widget integration | PASS |
| 7 | Study state survives JSON round-trip and corrupt JSON is tolerated | `study_state_store_test.dart` | File integration | PASS |
| 8 | Only card fields from words with frequency >= 40 are retained | `isdc_catalog_parser_test.dart`, `catalog_adapters_test.dart` | Parser/source integration | PASS |
| 9 | Fresh cache avoids network and stale cache survives source failure | `vocabulary_catalog_test.dart` | Unit/integration | PASS |
| 10 | Synchronized words reach rendering, rating persists, and the next card appears | `word_study_screen_test.dart` | Widget integration | PASS |
| 11 | Long words fit within 296 x 152 without truncation or overflow | `word_card_renderer_test.dart` | Rendering | PASS |
| 12 | Existing image-to-BLE workflow remains available separately | `widget_test.dart`, `word_study_screen_test.dart` | Widget regression | PASS |
| 13 | Phonetic and Chinese definition share a row, with the Chinese example below English | `word_card_renderer_test.dart` | Rendering | PASS |
| 14 | Existing Android secure storage remains addressable after the product rename | `project_identity_test.dart` | Build configuration | PASS |
| 15 | Cached or built-in words render before a slow network refresh completes | `vocabulary_catalog_test.dart`, `word_study_screen_test.dart` | Unit/widget integration | PASS |

## Final verification

- Full suite on 2026-08-03: `flutter test` -> 49 tests passed.
- Original scoped coverage run: `flutter test --coverage` -> 45 tests passed.
- Word feature line coverage: 512/613, 83.52%.
- Whole mobile app line coverage: 1014/1575, 64.38%. Existing BLE and editor
  platform branches account for most uncovered lines; the scoped word feature
  exceeds the 80% target.
- Static analysis: `flutter analyze` in the standalone ASCII-path repository ->
  no issues found.
- Android toolchain: `flutter doctor -v` recognizes SDK 36.0.0, JDK 17, and all
  accepted licenses. `flutter build apk --debug` produced
  `build/app/outputs/flutter-apk/app-debug.apk`.
- Formatting and whitespace: `dart format` and `git diff --check` passed.
- Android 16 emulator: version 1.0.1+2 installed and launched under the legacy
  package ID; the immediate fallback card showed the compact bilingual layout.

## Known gaps

- Android 16 emulator smoke testing verified notification permission, schedule
  persistence, APK launch, immediate first-sync fallback, bilingual card
  rendering, and rating persistence. Real 09:00 delivery, credential recovery,
  Brotli execution after a complete live download, and BLE upload still require
  an Android device test with the Quote/0.
- ISDC is a third-party page. Structured parser, cache, and failure behavior are
  tested, but future upstream schema changes can still require an adapter update.

## Merge evidence

Preserve the RED/GREEN pairs in the task report. If the branch is squash-merged,
copy that table and the final verification results into the pull request or
squash commit body.
