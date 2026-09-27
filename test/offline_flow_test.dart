import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yt_local_music/main.dart';
import 'package:yt_local_music/models/app_update.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/music_player_controller.dart';
import 'package:yt_local_music/screens/search_screen.dart';
import 'package:yt_local_music/services/download_manager.dart';
import 'package:yt_local_music/services/update_service.dart';
import 'package:yt_local_music/services/youtube_service.dart';

import 'fakes/fake_audio_engine.dart';

const _apiUrl = 'https://update.example.com/api/version';
const _downloadUrl = 'https://download.example.com/freevibe.apk';

/// Server-build + connectivity behavior all injected; no host network touched.
UpdateService _networkService({
  bool Function()? connectivityGate,
  int installedCode = 2,
  int serverCode = 2,
  bool forceUpdate = false,
  bool apiHttpError = false,
}) {
  final gate = connectivityGate ?? () => true;
  return UpdateService(
    apiUrl: _apiUrl,
    connectivityChecker: () async => gate(),
    versionLoader: () async =>
        AppVersion(versionName: '2.0.1', versionCode: installedCode),
    client: MockClient((request) async {
      if (request.url.host == 'connectivitycheck.gstatic.com') {
        return http.Response('', 204);
      }
      if (apiHttpError) {
        return http.Response('boom', 500);
      }
      return http.Response(
        '{"version":"2.1.0","versionCode":$serverCode,'
        '"downloadUrl":"$_downloadUrl","forceUpdate":$forceUpdate}',
        200,
      );
    }),
  );
}

Song _song(String id, String title) => Song(
  id: id,
  title: title,
  author: 'Artist',
  duration: '3:00',
  thumbnailUrl: '',
);

class _FakeYouTubeService extends YouTubeService {
  _FakeYouTubeService({List<Song>? page}) : page = page ?? <Song>[];

  final List<Song> page;
  int searchCalls = 0;
  int getVideoCalls = 0;
  int downloadAudioCalls = 0;

  @override
  Future<VideoSearchPage> searchVideos(String query) async {
    searchCalls++;
    return VideoSearchPage(page);
  }

  @override
  Future<Song> getVideo(String videoId) async {
    getVideoCalls++;
    return Song(
      id: videoId,
      title: 'Resolved $videoId',
      author: 'Artist',
      duration: '2:30',
      thumbnailUrl: '',
    );
  }

  @override
  Future<List<String>> getSearchSuggestions(String query) async => const [];

  @override
  Future<String> downloadAudio(Song song) async {
    downloadAudioCalls++;
    throw const DownloadUnavailableException('offline-flow test');
  }
}

void main() {
  late FakeAudioEngine engine;
  late MusicPlayerController player;

  setUp(() {
    engine = FakeAudioEngine();
    player = MusicPlayerController(engine: engine);
    player.init();
  });

  tearDown(() {
    player.dispose();
    engine.dispose();
    DownloadManager.instance.activeDownloads.clear();
  });

  Future<void> pumpSearch(
    WidgetTester tester,
    _FakeYouTubeService service,
    UpdateService updateService,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchScreen(
            youtubeService: service,
            playerController: player,
            updateService: updateService,
          ),
        ),
      ),
    );
  }

  Future<void> submitQuery(WidgetTester tester, String query) async {
    await tester.tap(find.byKey(const Key('search_launcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      find.byKey(const Key('search_overlay_field')),
      query,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 20));
  }

  Future<void> dismissOk(WidgetTester tester) async {
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  group('offline-first startup', () {
    testWidgets('app boots with no network and shows no alert', (tester) async {
      await tester.pumpWidget(
        MyApp(
          controller: player,
          updateService: _networkService(connectivityGate: () => false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsWidgets);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('No Internet Connection'), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });
  });

  group('offline search is blocked', () {
    testWidgets(
      'keyword search shows the network dialog, nothing hits YouTube',
      (tester) async {
        final service = _FakeYouTubeService(page: [_song('id-1', 'Song 1')]);
        await pumpSearch(
          tester,
          service,
          _networkService(connectivityGate: () => false),
        );

        await submitQuery(tester, 'coldplay');

        expect(find.text('No Internet Connection'), findsOneWidget);
        expect(
          find.textContaining('Internet connection is required to search'),
          findsOneWidget,
        );
        expect(service.searchCalls, 0);

        await dismissOk(tester);
        expect(service.searchCalls, 0);
      },
    );

    testWidgets('URL search is blocked before resolving the video', (
      tester,
    ) async {
      final service = _FakeYouTubeService();
      await pumpSearch(
        tester,
        service,
        _networkService(connectivityGate: () => false),
      );

      await submitQuery(tester, 'https://youtu.be/dQw4w9WgXcQ');

      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(service.getVideoCalls, 0);

      await dismissOk(tester);
      expect(service.getVideoCalls, 0);
    });
  });

  group('online search gates and update check', () {
    testWidgets('search runs and no update dialog when server build matches', (
      tester,
    ) async {
      final service = _FakeYouTubeService(page: [_song('id-1', 'Song 1')]);
      await pumpSearch(tester, service, _networkService());

      await submitQuery(tester, 'coldplay');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.searchCalls, 1);
      expect(find.text('Song 1'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('optional update prompts after search succeeds', (
      tester,
    ) async {
      final service = _FakeYouTubeService(page: [_song('id-1', 'Song 1')]);
      await pumpSearch(tester, service, _networkService(serverCode: 9));

      await submitQuery(tester, 'coldplay');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.searchCalls, 1);
      expect(find.text('Song 1'), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('forced update prompts and blocks dismissal', (tester) async {
      final service = _FakeYouTubeService(page: [_song('id-1', 'Song 1')]);
      await pumpSearch(
        tester,
        service,
        _networkService(serverCode: 9, forceUpdate: true),
      );

      await submitQuery(tester, 'coldplay');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    });

    testWidgets('update API failure is invisible and search still works', (
      tester,
    ) async {
      final service = _FakeYouTubeService(page: [_song('id-1', 'Song 1')]);
      await pumpSearch(tester, service, _networkService(apiHttpError: true));

      await submitQuery(tester, 'coldplay');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.searchCalls, 1);
      expect(find.text('Song 1'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });
  });

  group('offline preview and download are blocked', () {
    testWidgets('preview shows the network dialog and never starts streaming', (
      tester,
    ) async {
      var online = true;
      final service = _FakeYouTubeService(page: [_song('id-1', 'Song 1')]);
      await pumpSearch(
        tester,
        service,
        _networkService(connectivityGate: () => online),
      );
      await submitQuery(tester, 'coldplay');
      expect(find.text('Song 1'), findsOneWidget);

      online = false;
      await tester.tap(find.byTooltip('Preview').first);
      await tester.pumpAndSettle();

      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(
        find.textContaining('Internet connection is required for preview'),
        findsOneWidget,
      );
      expect(player.currentSong, isNull);

      await dismissOk(tester);
      expect(player.currentSong, isNull);
    });

    testWidgets(
      'download shows the network dialog and never starts the downloader',
      (tester) async {
        var online = true;
        final service = _FakeYouTubeService(page: [_song('id-1', 'Song 1')]);
        await pumpSearch(
          tester,
          service,
          _networkService(connectivityGate: () => online),
        );
        await submitQuery(tester, 'coldplay');
        expect(find.text('Song 1'), findsOneWidget);

        online = false;
        await tester.tap(find.byTooltip('Download').first);
        await tester.pumpAndSettle();

        expect(find.text('No Internet Connection'), findsOneWidget);
        expect(
          find.textContaining('Internet connection is required to download'),
          findsOneWidget,
        );
        expect(service.downloadAudioCalls, 0);
        expect(DownloadManager.instance.activeDownloads['id-1'], isNull);

        await dismissOk(tester);
        expect(service.downloadAudioCalls, 0);
        expect(DownloadManager.instance.activeDownloads['id-1'], isNull);
      },
    );
  });

  group('connectivity recovery', () {
    testWidgets('offline -> online -> offline works without restart', (
      tester,
    ) async {
      var online = false;
      final service = _FakeYouTubeService(page: [_song('id-1', 'Song 1')]);
      await pumpSearch(
        tester,
        service,
        _networkService(connectivityGate: () => online),
      );

      await submitQuery(tester, 'coldplay');
      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(service.searchCalls, 0);
      await dismissOk(tester);

      online = true;
      await submitQuery(tester, 'coldplay');
      expect(service.searchCalls, 1);
      expect(find.text('Song 1'), findsOneWidget);

      online = false;
      await submitQuery(tester, 'radiohead');
      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(service.searchCalls, 1);
      await dismissOk(tester);

      online = true;
      await submitQuery(tester, 'radiohead');
      expect(service.searchCalls, 2);
      expect(find.text('Song 1'), findsOneWidget);
    });
  });
}
