import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/app_update.dart';

void main() {
  group('AppUpdate.tryParse', () {
    const validJson = '''
{
  "version": "2.1.0",
  "versionCode": 8,
  "downloadUrl": "https://github.com/acme/freevibe/releases/download/v2.1.0/freevibe.apk",
  "forceUpdate": true
}
''';

    test('parses a valid payload', () {
      final update = AppUpdate.tryParse(validJson);
      expect(update, isNotNull);
      expect(update!.version, '2.1.0');
      expect(update.versionCode, 8);
      expect(update.downloadUrl, contains('github.com'));
      expect(update.forceUpdate, isTrue);
    });

    test('accepts extra unknown fields', () {
      final update = AppUpdate.tryParse(
        '{"version":"1.0.0","versionCode":1,'
        '"downloadUrl":"https://example.com/a.apk",'
        '"forceUpdate":false,"notes":"changelog"}',
      );
      expect(update, isNotNull);
    });

    test('rejects a missing version', () {
      expect(AppUpdate.tryParse(validJson.replaceFirst('"version": "2.1.0",', '')), isNull);
    });

    test('rejects an empty version', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst('"2.1.0"', '"  "')),
        isNull,
      );
    });

    test('rejects a missing versionCode', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst('"versionCode": 8,', '')),
        isNull,
      );
    });

    test('rejects a non-integer versionCode', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst('"versionCode": 8', '"versionCode": "8"')),
        isNull,
      );
    });

    test('rejects a non-positive versionCode', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst('"versionCode": 8', '"versionCode": 0')),
        isNull,
      );
    });

    test('rejects a missing downloadUrl', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst(
          '"downloadUrl": "https://github.com/acme/freevibe/releases/download/v2.1.0/freevibe.apk",',
          '',
        )),
        isNull,
      );
    });

    test('rejects a non-https downloadUrl', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst('https://', 'http://')),
        isNull,
      );
    });

    test('rejects a malformed downloadUrl', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst(
          'https://github.com/acme/freevibe/releases/download/v2.1.0/freevibe.apk',
          'not a url',
        )),
        isNull,
      );
    });

    test('rejects a missing forceUpdate', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst('"forceUpdate": true', '')),
        isNull,
      );
    });

    test('rejects a non-bool forceUpdate', () {
      expect(
        AppUpdate.tryParse(validJson.replaceFirst('"forceUpdate": true', '"forceUpdate": "yes"')),
        isNull,
      );
    });

    test('rejects invalid JSON', () {
      expect(AppUpdate.tryParse('this is not json'), isNull);
    });

    test('rejects a JSON array', () {
      expect(AppUpdate.tryParse('[1,2,3]'), isNull);
    });

    test('rejects a JSON number', () {
      expect(AppUpdate.tryParse('42'), isNull);
    });
  });

  group('isUpdateAvailable (versionCode comparison)', () {
    test('newer server code -> update available', () {
      expect(
        isUpdateAvailable(installedCode: 2, serverCode: 3),
        isTrue,
      );
    });

    test('same code -> no update', () {
      expect(
        isUpdateAvailable(installedCode: 8, serverCode: 8),
        isFalse,
      );
    });

    test('older server code -> no update', () {
      expect(
        isUpdateAvailable(installedCode: 8, serverCode: 2),
        isFalse,
      );
    });

    test('handles large build numbers', () {
      expect(
        isUpdateAvailable(installedCode: 102409, serverCode: 102410),
        isTrue,
      );
    });
  });
}