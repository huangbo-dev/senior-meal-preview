import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senior_meal_preview/main.dart';

void main() {
  test('About version matches pubspec and the changelog', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([0-9.]+)\+',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
    expect(
      File('../CHANGELOG.md').readAsStringSync(),
      contains('## $appVersion '),
    );
  });
}
