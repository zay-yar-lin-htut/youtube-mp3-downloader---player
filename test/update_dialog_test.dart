import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yt_local_music/models/app_update.dart';
import 'package:yt_local_music/screens/update_dialog.dart';
import 'package:yt_local_music/services/update_service.dart';

const _downloadUrl = 'https://download.example.com/freevibe.apk';
const _installed = AppVersion(versionName: '2.0.1', versionCode: 2);

UpdateCheck _check({int versionCode = 9, bool forceUpdate = false}) =>
    UpdateCheck(
      installed: _installed,
      server: AppUpdate(
        version: '2.1.0',
        versionCode: versionCode,
        downloadUrl: _downloadUrl,
        forceUpdate: forceUpdate,
      ),
      available: true,
    );

UpdateService _dialogService({
  required http.Client client,
  Future<bool> Function(String)? installer,
}) {
  return UpdateService(
    apiUrl: 'https://update.example.com/api/version',
    client: client,
    connectivityChecker: () async => true,
    versionLoader: () async => _installed,
    installLauncher: installer ?? (_) async => true,
    cacheDirProvider: () async =>
        Directory.systemTemp.createTempSync('update_dialog_test'),
  );
}

Widget _app({required Future<void> Function() onOpen}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(onPressed: onOpen, child: const Text('go')),
        ),
      ),
    ),
  );
}

/// Lets the real event loop run so real dart:io file operations (which do not
/// progress under the widget-test fake-async zone) can complete. Each round is
/// one real-timer yield followed by a pump that flushes the fake zone's
/// microtasks, so the download chain (dir->send->flush->close->rename) makes
/// progress hop by hop.
Future<void> _pumpWithRealAsync(
  WidgetTester tester, [
  int rounds = 6,
]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

void main() {
  group('runUpdateFlowIfNeeded', () {
    testWidgets('shows nothing when the server build is not newer', (tester) async {
      final client = MockClient((_) async => http.Response(
            '{"version":"2.0.1","versionCode":2,'
            '"downloadUrl":"$_downloadUrl","forceUpdate":false}',
            200,
          ));
      final service = _dialogService(client: client);
      await tester.pumpWidget(_app(
        onOpen: () async =>
            runUpdateFlowIfNeeded(tester.element(find.byType(Scaffold)), service: service),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('shows the optional prompt when an update exists', (tester) async {
      final client = MockClient((_) async => http.Response(
            '{"version":"2.1.0","versionCode":9,'
            '"downloadUrl":"$_downloadUrl","forceUpdate":false}',
            200,
          ));
      final service = _dialogService(client: client);
      await tester.pumpWidget(_app(
        onOpen: () async =>
            runUpdateFlowIfNeeded(tester.element(find.byType(Scaffold)), service: service),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });
  });

  group('UpdateFlowDialog prompt', () {
    testWidgets('optional update offers Later and can be dismissed', (tester) async {
      final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
      await tester.pumpWidget(_app(
        onOpen: () async => showUpdateDialog(
          tester.element(find.byType(Scaffold)),
          service: _dialogService(client: client),
          check: _check(),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('FreeVibe 2.1.0 (build 9) is here.'), findsOneWidget);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('forced update hides Later and blocks dismissal', (tester) async {
      final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
      await tester.pumpWidget(_app(
        onOpen: () async => showUpdateDialog(
          tester.element(find.byType(Scaffold)),
          service: _dialogService(client: client),
          check: _check(forceUpdate: true),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(find.text('Update'), findsOneWidget);
    });
  });

  group('UpdateFlowDialog download flow', () {
    testWidgets('shows progress while streaming and completes the installer',
        (tester) async {
      final stream = StreamController<List<int>>();
      final client = _StreamClient(
        () async => http.StreamedResponse(
          http.ByteStream(stream.stream),
          200,
          contentLength: 2048,
        ),
      );
      final installerCalls = <String>[];
      await tester.pumpWidget(_app(
        onOpen: () async => showUpdateDialog(
          tester.element(find.byType(Scaffold)),
          service: _dialogService(
            client: client,
            installer: (path) async {
              installerCalls.add(path);
              return true;
            },
          ),
          check: _check(),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(find.text('Downloading update'), findsOneWidget);

      // Let the real event loop advance the file I/O until the download
      // chain is listening on the stream.
      await _pumpWithRealAsync(tester);

      await tester.runAsync(() async {
        stream.add(List<int>.generate(1024, (i) => i));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      expect(find.textContaining('1.0 KB'), findsOneWidget);

      await tester.runAsync(() async {
        stream.add(List<int>.generate(1024, (i) => i));
        unawaited(stream.close());
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await _pumpWithRealAsync(tester);

      expect(find.text('Ready to install'), findsOneWidget);
      expect(installerCalls, hasLength(1));
      expect(installerCalls.single, endsWith('freevibe_update.apk'));
    });

    testWidgets('failed download shows Retry which then succeeds', (tester) async {
      var fail = true;
      final client = MockClient((_) async {
        if (fail) return http.Response('gone', 404);
        return http.Response.bytes([1, 2, 3], 200);
      });
      final installerCalls = <String>[];
      await tester.pumpWidget(_app(
        onOpen: () async => showUpdateDialog(
          tester.element(find.byType(Scaffold)),
          service: _dialogService(
            client: client,
            installer: (path) async {
              installerCalls.add(path);
              return true;
            },
          ),
          check: _check(),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pump();
      await _pumpWithRealAsync(tester);
      await tester.pump();

      expect(find.text('Update failed'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await _pumpWithRealAsync(tester);
      await tester.pump();

      expect(find.text('Ready to install'), findsOneWidget);
      expect(installerCalls, hasLength(1));
    });

    testWidgets('installer launch failure surfaces a clear message', (tester) async {
      final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
      await tester.pumpWidget(_app(
        onOpen: () async => showUpdateDialog(
          tester.element(find.byType(Scaffold)),
          service: _dialogService(client: client, installer: (_) async => false),
          check: _check(),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pump();
      await _pumpWithRealAsync(tester);
      await tester.pump();

      expect(find.text('Update failed'), findsOneWidget);
      expect(find.textContaining('Install unknown apps'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}

/// Client that streams a response body controlled by the test.
class _StreamClient extends http.BaseClient {
  _StreamClient(this._handler);

  final Future<http.StreamedResponse> Function() _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _handler();
}