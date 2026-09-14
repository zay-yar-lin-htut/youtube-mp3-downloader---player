import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:yt_local_music/models/app_update.dart';
import 'package:yt_local_music/services/update_service.dart';

const _apiUrl = 'https://update.example.com/api/version';
const _downloadUrl = 'https://download.example.com/freevibe.apk';
const _installed = AppVersion(versionName: '2.0.1', versionCode: 2);

Future<bool> _online() async => true;
Future<bool> _offline() async => false;

String _payload({int versionCode = 3, bool forceUpdate = false}) =>
    '{"version":"2.1.0","versionCode":$versionCode,'
    '"downloadUrl":"$_downloadUrl","forceUpdate":$forceUpdate}';

Directory _freshTempDir() =>
    Directory.systemTemp.createTempSync('update_test');

Future<Directory> _freshTempDirAsync() async =>
    Directory.systemTemp.createTempSync('update_test');

UpdateService _service({
  required http.Client client,
  UpdateConnectivityChecker connectivityChecker = _online,
  Future<bool> Function(String)? installer,
  AppVersion installed = _installed,
  Future<Directory> Function()? cacheDirProvider,
  Duration apiTimeout = updateApiTimeout,
}) {
  return UpdateService(
    apiUrl: _apiUrl,
    client: client,
    connectivityChecker: connectivityChecker,
    versionLoader: () async => installed,
    installLauncher: installer ?? (_) async => true,
    cacheDirProvider: cacheDirProvider ?? _freshTempDirAsync,
    apiTimeout: apiTimeout,
  );
}

/// HTTP client whose requests stay pending until [complete] is called.
class _PendingClient extends http.BaseClient {
  final Completer<void> _ready = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _ready.future;
    final body = request.headers.containsKey('download')
        ? List<int>.generate(16, (i) => i)
        : _payload(versionCode: 3).codeUnits;
    return http.StreamedResponse(
      http.ByteStream.fromBytes(body),
      200,
      contentLength: body.length,
    );
  }

  void complete() {
    if (!_ready.isCompleted) _ready.complete();
  }
}

void main() {
  group('UpdateService.checkForUpdate', () {
    test('returns null when there is no network and hits no API', () async {
      var hits = 0;
      final client = MockClient((_) async {
        hits++;
        return http.Response(_payload(), 200);
      });
      final service = _service(client: client, connectivityChecker: _offline);
      expect(await service.checkForUpdate(), isNull);
      expect(hits, 0);
    });

    test('returns null on non-200 API response', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      final service = _service(client: client);
      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null on a malformed payload', () async {
      final client =
          MockClient((_) async => http.Response('{"version": 42}', 200));
      final service = _service(client: client);
      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when installed version cannot be read', () async {
      final client = MockClient((_) async => http.Response(_payload(), 200));
      final service = UpdateService(
        apiUrl: _apiUrl,
        client: client,
        connectivityChecker: _online,
        versionLoader: () async => throw StateError('no package info'),
      );
      expect(await service.checkForUpdate(), isNull);
    });

    test('no update when server build is not newer', () async {
      final client = MockClient(
        (_) async => http.Response(_payload(versionCode: 2), 200),
      );
      final service = _service(client: client);
      final check = await service.checkForUpdate();
      expect(check, isNotNull);
      expect(check!.available, isFalse);
      expect(check.installed.versionCode, 2);
      expect(check.server.versionCode, 2);
    });

    test('update available when server build is newer', () async {
      final client = MockClient(
        (_) async => http.Response(_payload(versionCode: 9), 200),
      );
      final service = _service(client: client);
      final check = await service.checkForUpdate();
      expect(check, isNotNull);
      expect(check!.available, isTrue);
      expect(check.server.version, '2.1.0');
      expect(check.server.downloadUrl, _downloadUrl);
      expect(check.server.forceUpdate, isFalse);
    });

    test('a pending API request times out', () async {
      final client = _PendingClient();
      final service =
          _service(client: client, apiTimeout: const Duration(milliseconds: 40));
      final start = DateTime.now();
      expect(await service.checkForUpdate(), isNull);
      expect(DateTime.now().difference(start).inMilliseconds, lessThan(2000));
      client.complete();
    });

    test('guard: second concurrent check returns null (away pending timer)',
        () async {
      final client = _PendingClient();
      final service =
          _service(client: client, apiTimeout: const Duration(minutes: 5));
      final first = service.checkForUpdate();
      final second = await service.checkForUpdate();
      expect(second, isNull);
      expect(service.checkInProgress, isTrue);
      client.complete();
      final firstResult = await first;
      expect(firstResult, isNotNull);
      expect(firstResult!.available, isTrue);
      expect(service.checkInProgress, isFalse);
    });
  });

  group('UpdateService.downloadUpdate', () {
    test('downloads to cache dir and renames .part away', () async {
      final dir = _freshTempDir();
      final client = MockClient(
        (_) async => http.Response.bytes([1, 2, 3, 4], 200),
      );
      final service = _service(client: client, cacheDirProvider: () async => dir);

      final values = <int>[];
      final result = await service.downloadUpdate(
        _downloadUrl,
        onProgress: (received, total) {
          values.add(received);
          expect(total, 4);
        },
      );

      expect(result, isNotNull);
      expect(result!.filePath, p.join(dir.path, 'freevibe_update.apk'));
      expect(File(result.filePath).readAsBytesSync(), [1, 2, 3, 4]);
      expect(
        File(p.join(dir.path, 'freevibe_update.apk.part')).existsSync(),
        isFalse,
      );
      expect(values, [4]);
    });

    test('returns null on HTTP error and leaves no .part behind', () async {
      final dir = _freshTempDir();
      final client = MockClient((_) async => http.Response('gone', 404));
      final service = _service(client: client, cacheDirProvider: () async => dir);

      final result = await service.downloadUpdate(_downloadUrl);

      expect(result, isNull);
      final leftovers = dir
          .listSync()
          .where((e) => e.path.endsWith('freevibe_update.apk.part'));
      expect(leftovers, isEmpty);
    });

    test('returns null when received size mismatches Content-Length', () async {
      final dir = _freshTempDir();
      final client = _SizeMismatchClient();
      final service = _service(client: client, cacheDirProvider: () async => dir);

      final result = await service.downloadUpdate(_downloadUrl);

      expect(result, isNull);
      expect(
        dir.listSync().where((e) => e.path.endsWith('.part')),
        isEmpty,
      );
    });

    test('returned APK is removed from disk after a failed download', () async {
      final dir = _freshTempDir();
      final client = _SizeMismatchClient();
      final service = _service(client: client, cacheDirProvider: () async => dir);
      await service.downloadUpdate(_downloadUrl);
      expect(
        dir.listSync().where((e) => e.path.endsWith('freevibe_update.apk')),
        isEmpty,
      );
    });

    test('guard: concurrent download returns null', () async {
      final client = _PendingClient();
      final service = _service(client: client);
      final first = service.downloadUpdate(_downloadUrl);
      final second = await service.downloadUpdate(_downloadUrl);
      expect(second, isNull);
      expect(service.downloadInProgress, isTrue);
      client.complete();
      final firstResult = await first;
      expect(firstResult, isNotNull);
      expect(service.downloadInProgress, isFalse);
    });
  });

  group('UpdateService.launchInstaller', () {
    test('delegates to the injected launcher', () async {
      final calls = <String>[];
      final service = _service(
        client: MockClient((_) async => http.Response('', 200)),
        installer: (path) async {
          calls.add(path);
          return true;
        },
      );
      expect(await service.launchInstaller('/tmp/freevibe.apk'), isTrue);
      expect(calls, ['/tmp/freevibe.apk']);
    });

    test('propagates launch failure', () async {
      final service = _service(
        client: MockClient((_) async => http.Response('', 200)),
        installer: (_) async => false,
      );
      expect(await service.launchInstaller('/tmp/freevibe.apk'), isFalse);
    });
  });

  group('UpdateService.hasInternetConnection', () {
    const probe = 'https://connectivitycheck.gstatic.com/generate_204';

    test('connectivity reports offline -> false without probing', () async {
      var probed = false;
      final service = _service(
        connectivityChecker: _offline,
        client: MockClient((request) async {
          probed = true;
          return http.Response('', 204);
        }),
      );
      expect(await service.hasInternetConnection(probeUrl: probe), isFalse);
      expect(probed, isFalse);
    });

    test('online connectivity + reachable probe -> true', () async {
      final service = _service(
        client: MockClient((request) async => http.Response('', 204)),
      );
      expect(await service.hasInternetConnection(probeUrl: probe), isTrue);
    });

    test('online connectivity + failing probe -> false', () async {
      final service = _service(
        client: MockClient((request) async => http.Response('nope', 500)),
      );
      expect(await service.hasInternetConnection(probeUrl: probe), isFalse);
    });

    test('connectivity check error falls back to the probe', () async {
      final service = _service(
        connectivityChecker: () async => throw StateError('plugin dead'),
        client: MockClient((request) async => http.Response('', 204)),
      );
      expect(await service.hasInternetConnection(probeUrl: probe), isTrue);
    });

    test('timed-out probe -> false', () async {
      final service = _service(
        client: _PendingClient(),
      );
      final result = await service.hasInternetConnection(
        probeUrl: probe,
        timeout: const Duration(milliseconds: 1),
      );
      expect(result, isFalse);
    });
  });
}

/// Client that advertises 100 bytes but only streams 4.
class _SizeMismatchClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      http.ByteStream.fromBytes([1, 2, 3, 4]),
      200,
      contentLength: 100,
    );
  }
}