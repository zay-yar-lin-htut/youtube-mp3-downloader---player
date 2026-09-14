import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/music_player_controller.dart';
import 'package:yt_local_music/screens/search_screen.dart';
import 'package:yt_local_music/services/youtube_service.dart';

import 'fakes/fake_audio_engine.dart';

Song _song(String id, String title) => Song(
      id: id,
      title: title,
      author: 'Artist',
      duration: '3:00',
      thumbnailUrl: '',
    );

/// Stubbed search backend: no live network. `nextSearchPage` is gated by an
/// optional completer so in-flight pagination can be controlled in tests.
class _FakeYouTubeService extends YouTubeService {
  _FakeYouTubeService({
    List<Song>? page,
    this.loadMoreGate,
    this.suggestionsGate,
  }) : page = page ?? <Song>[];

  final List<Song> page;
  Completer<void>? loadMoreGate;
  Completer<void>? suggestionsGate;

  int searchCalls = 0;
  int nextPageCalls = 0;
  int getVideoCalls = 0;

  @override
  Future<VideoSearchPage> searchVideos(String query) async {
    searchCalls++;
    return VideoSearchPage(page);
  }

  @override
  Future<VideoSearchPage?> nextSearchPage(VideoSearchPage page) async {
    nextPageCalls++;
    final gate = loadMoreGate;
    if (gate != null) {
      await gate.future;
    }
    return null; // exhausted
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
  Future<List<String>> getSearchSuggestions(String query) async {
    final gate = suggestionsGate;
    if (gate != null) {
      await gate.future;
    }
    return const [];
  }
}

List<Song> _bigPage(int count) =>
    List.generate(count, (i) => _song('id-$i', 'Song $i'));

class _RateLimitedService extends _FakeYouTubeService {
  _RateLimitedService({super.page});

  @override
  Future<String> downloadAudio(Song song) async {
    throw const DownloadRateLimitedException(
        'Download temporarily limited by YouTube. Please try again shortly.');
  }
}

class _UnavailableService extends _FakeYouTubeService {
  _UnavailableService({super.page});

  @override
  Future<String> downloadAudio(Song song) async {
    throw const DownloadUnavailableException(
        'This video is unavailable. Try a different result.');
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
  });

  Future<void> pumpSearch(
    WidgetTester tester,
    _FakeYouTubeService service,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchScreen(
            youtubeService: service,
            playerController: player,
          ),
        ),
      ),
    );
  }

  Future<void> openSearchOverlay(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('search_launcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> submitQuery(WidgetTester tester, String query) async {
    await openSearchOverlay(tester);
    await tester.enterText(
      find.byKey(const Key('search_overlay_field')),
      query,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 20));
  }

  group('SearchScreen pagination', () {
    testWidgets('fetches results, then paginates once and stops', (
      tester,
    ) async {
      final service = _FakeYouTubeService(page: _bigPage(40));
      await pumpSearch(tester, service);

      await submitQuery(tester, 'coldplay');
      expect(service.searchCalls, 1);
      expect(find.text('Song 0'), findsOneWidget);

      // Scroll near the end -> triggers one pagination fetch.
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(service.nextPageCalls, 1);

      // Page exhausted -> footer shows the end state, no more fetches.
      expect(find.text('End of results'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(service.nextPageCalls, 1);
    });

    testWidgets('a second scroll while a page is loading does not refetch', (
      tester,
    ) async {
      final service = _FakeYouTubeService(
        page: _bigPage(40),
        loadMoreGate: Completer<void>(),
      );
      await pumpSearch(tester, service);
      await submitQuery(tester, 'coldplay');

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump();
      expect(service.nextPageCalls, 1);

      // Extra scroll notifications while the in-flight page is pending.
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(service.nextPageCalls, 1);

      service.loadMoreGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(service.nextPageCalls, 1);
      expect(find.text('End of results'), findsOneWidget);
    });
  });

  group('SearchScreen URL search', () {
    testWidgets('a YouTube URL resolves a single video via getVideo', (
      tester,
    ) async {
      final service = _FakeYouTubeService();
      await pumpSearch(tester, service);

      await submitQuery(tester, 'https://youtu.be/dQw4w9WgXcQ');
      expect(service.getVideoCalls, 1);
      expect(service.searchCalls, 0);
      expect(find.text('Resolved dQw4w9WgXcQ'), findsOneWidget);
    });
  });

  group('SearchScreen suggestions', () {
    testWidgets('overwriting with a URL hides the busy indicator', (
      tester,
    ) async {
      final service = _FakeYouTubeService(
        suggestionsGate: Completer<void>(),
      );
      await pumpSearch(tester, service);

      // Open the overlay and type a keyword: suggestions stay busy.
      await openSearchOverlay(tester);
      await tester.enterText(
        find.byKey(const Key('search_overlay_field')),
        'coldplay',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Searching…'), findsOneWidget);

      // Overwriting with a URL must stop the busy state even while pending.
      await tester.enterText(
        find.byKey(const Key('search_overlay_field')),
        'https://youtu.be/dQw4w9WgXcQ',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Searching…'), findsNothing);
    });

    testWidgets('dismissing the overlay without searching keeps results', (
      tester,
    ) async {
      final service = _FakeYouTubeService(page: _bigPage(3));
      await pumpSearch(tester, service);
      await submitQuery(tester, 'coldplay');
      expect(find.text('Song 0'), findsOneWidget);

      // Re-open and just close it (back arrow): previous results must remain.
      await openSearchOverlay(tester);
      final backButton = find.byTooltip('Close search');
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Song 0'), findsOneWidget);
    });

    testWidgets('tapping the barrier dismisses the overlay without playing', (
      tester,
    ) async {
      final service = _FakeYouTubeService(page: _bigPage(3));
      await pumpSearch(tester, service);
      await submitQuery(tester, 'coldplay');
      expect(find.text('Song 0'), findsOneWidget);

      await openSearchOverlay(tester);
      expect(find.byKey(const Key('search_overlay_field')), findsOneWidget);

      // A tap on the (dimmed) background closes the overlay, and the tap must
      // NOT reach the search results underneath (no preview started).
      final screenSize = tester.getSize(find.byType(SearchScreen));
      await tester.tapAt(
        Offset(screenSize.width / 2, screenSize.height - 60),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('search_overlay_field')), findsNothing);
      expect(player.currentSong, isNull);
      expect(find.text('Song 0'), findsOneWidget);
    });
  });

  group('SearchScreen clear (X) button', () {
    Finder searchButton() => find.descendant(
          of: find.byKey(const Key('search_overlay_field')),
          matching: find.byKey(const Key('search_action')),
        );

    Finder clearButton() => find.descendant(
          of: find.byKey(const Key('search_overlay_field')),
          matching: find.byKey(const Key('search_clear')),
        );

    TextEditingController fieldController(WidgetTester tester) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(const Key('search_overlay_field')),
            matching: find.byType(TextField),
          ),
        )
        .controller!;

    testWidgets('empty field shows the search icon, not the clear icon', (
      tester,
    ) async {
      await pumpSearch(tester, _FakeYouTubeService());
      await openSearchOverlay(tester);

      expect(searchButton(), findsOneWidget);
      expect(clearButton(), findsNothing);
    });

    testWidgets('typing text replaces the search icon with the clear icon', (
      tester,
    ) async {
      await pumpSearch(tester, _FakeYouTubeService());
      await openSearchOverlay(tester);

      await tester.enterText(
        find.byKey(const Key('search_overlay_field')),
        'rick astley',
      );
      await tester.pump();

      expect(clearButton(), findsOneWidget);
      expect(searchButton(), findsNothing);
    });

    testWidgets(
      'tapping the clear icon empties the field, restores the search icon, '
      'and does not trigger a search',
      (tester) async {
        final service = _FakeYouTubeService(page: _bigPage(3));
        await pumpSearch(tester, service);
        await openSearchOverlay(tester);

        await tester.enterText(
          find.byKey(const Key('search_overlay_field')),
          'rick astley',
        );
        await tester.pump();
        expect(clearButton(), findsOneWidget);

        await tester.tap(clearButton());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        // Field cleared, lens back, overlay still open, nothing searched.
        expect(fieldController(tester).text, isEmpty);
        expect(searchButton(), findsOneWidget);
        expect(clearButton(), findsNothing);
        expect(find.byKey(const Key('search_overlay_field')), findsOneWidget);
        expect(service.searchCalls, 0);
        expect(service.getVideoCalls, 0);
        expect(player.currentSong, isNull);
      },
    );

    testWidgets(
      'tapping the clear icon cancels an in-flight suggestion request',
      (tester) async {
        final service = _FakeYouTubeService(
          suggestionsGate: Completer<void>(),
        );
        await pumpSearch(tester, service);
        await openSearchOverlay(tester);

        await tester.enterText(
          find.byKey(const Key('search_overlay_field')),
          'coldplay',
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Searching…'), findsOneWidget);

        await tester.tap(clearButton());
        await tester.pump(const Duration(milliseconds: 400));

        // Pending suggestions resolve only to an already-cancelled request:
        // the field stays empty and the busy indicator never reappears.
        expect(find.text('Searching…'), findsNothing);
        service.suggestionsGate!.complete();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Searching…'), findsNothing);
        expect(fieldController(tester).text, isEmpty);
      },
    );

    testWidgets('searching still works after using the clear icon', (
      tester,
    ) async {
      final service = _FakeYouTubeService(page: _bigPage(3));
      await pumpSearch(tester, service);

      // Type, clear, then submit a fresh query: results must still load.
      await openSearchOverlay(tester);
      await tester.enterText(
        find.byKey(const Key('search_overlay_field')),
        'ignore me',
      );
      await tester.pump();
      await tester.tap(clearButton());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('search_overlay_field')),
        'coldplay',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 20));

      expect(service.searchCalls, 1);
      expect(find.text('Song 0'), findsOneWidget);
    });
  });

  group('SearchScreen download messaging', () {
    testWidgets('rate limit shows a friendly message, not a generic failure', (
      tester,
    ) async {
      final service = _RateLimitedService(page: _bigPage(2));
      await pumpSearch(tester, service);
      await submitQuery(tester, 'coldplay');

      await tester.tap(find.byTooltip('Download').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(
        find.text(
          'Download temporarily limited by YouTube. Please try again shortly.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('All download candidates'), findsNothing);
    });

    testWidgets('unavailable video shows its own distinct message', (
      tester,
    ) async {
      final service = _UnavailableService(page: _bigPage(2));
      await pumpSearch(tester, service);
      await submitQuery(tester, 'coldplay');

      await tester.tap(find.byTooltip('Download').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(
        find.text('This video is unavailable. Try a different result.'),
        findsOneWidget,
      );
    });
  });
}
