import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QuoteWords preserves the legacy Android storage identity', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final androidBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/tech/undef/quotewords/MainActivity.kt',
    );

    expect(pubspec, contains('name: quotewords'));
    expect(pubspec, contains('description: QuoteWords'));
    expect(pubspec, contains('version: 1.0.2+3'));
    expect(androidBuild, contains('namespace = "tech.undef.quotewords"'));
    expect(androidBuild, contains('applicationId = "tech.undef.quoteimage"'));
    expect(androidManifest, contains('android:label="QuoteWords"'));
    expect(mainActivity.existsSync(), isTrue);
    expect(
      mainActivity.readAsStringSync(),
      contains('package tech.undef.quotewords'),
    );
  });
}
