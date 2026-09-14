import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yt_local_music/main.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/music_player_controller.dart';
import 'package:yt_local_music/widgets/song_tile.dart';

import 'fakes/fake_audio_engine.dart';

Song _song(String id, {String? path}) => Song(
      id: id,
      title: 'Song $id',
      author: 'Artist',
      duration: '3:21',
      thumbnailUrl: '',
      localPath: path ?? '/tmp/$id.m4a',
    );

Widget _app(MusicPlayerController controller) {
  return MyApp(controller: controller);
}

void main() {
  testWidgets('App renders search, downloads and playlist navigation',
      (tester) async {
    final controller = MusicPlayerController(engine: FakeAudioEngine());
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Search'), findsWidgets);

    // Mini player is hidden while nothing is playing.
    expect(find.text('Song a'), findsNothing);

    // Playlist root shows system views + custom playlists.
    await tester.tap(find.text('Playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('On device'), findsOneWidget);

    // Tapping 'All' opens the detail screen with the empty pane.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('No music yet'), findsOneWidget);

    // Detail app bar keeps the standard filter control separate from Sort.
    expect(find.byTooltip('Filter'), findsOneWidget);
    expect(find.byTooltip('Sort'), findsOneWidget);

    // The playlist detail stays inside the app shell: the bottom navigation
    // bar remains visible (not hidden by a full-screen pushed route).
    expect(find.byType(NavigationBar), findsOneWidget);

    // Pop back to root, then back to Search.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search_launcher')), findsOneWidget);
  });

  testWidgets('Playing a song shows the mini player and opens Now Playing',
      (tester) async {
    final controller = MusicPlayerController(engine: FakeAudioEngine());
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
    await tester.pumpAndSettle();

    // Mini player surfaces the current track.
    expect(find.text('Song a'), findsOneWidget);

    // Tapping the mini player opens the full-screen page.
    await tester.tap(find.text('Song a'));
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Song a'), findsWidgets);

    // Collapse back.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsNothing);

    await controller.stopAndClear();
    await tester.pumpAndSettle();
    expect(find.text('Song a'), findsNothing);
  });

  testWidgets('Auto-advances to next track as engine completes',
      (tester) async {
    final engine = FakeAudioEngine();
    final controller = MusicPlayerController(engine: engine);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await controller.playLocalList([
      _song('a', path: '/tmp/a.m4a'),
      _song('b', path: '/tmp/b.m4a'),
    ]);
    await tester.pumpAndSettle();

    // move to next track through the engine completing
    engine.complete();
    await tester.pumpAndSettle();
    expect(controller.currentSong!.id, 'b');
    expect(find.text('Song b'), findsWidgets);
  });

  testWidgets('Sleep timer starts and shows in Now Playing',
      (tester) async {
    final controller = MusicPlayerController(
      engine: FakeAudioEngine(),
      clock: () => DateTime(2025, 1, 1, 12, 0, 0),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
    await tester.pumpAndSettle();

    // Start a 15 minute sleep timer via the controller.
    controller.startSleepTimer(const Duration(minutes: 15));
    expect(controller.hasSleepTimer, isTrue);
    expect(controller.sleepTimerEndsAt, DateTime(2025, 1, 1, 12, 15, 0));

    // The remaining duration reflects the 15 minutes.
    final remaining = controller.sleepTimerRemaining;
    expect(remaining, isNotNull);
    expect(remaining!.inMinutes, 15);

    // Cancel restores the state.
    controller.cancelSleepTimer();
    expect(controller.hasSleepTimer, isFalse);
    expect(controller.sleepTimerRemaining, isNull);

    // The sheet in Now Playing exposes presets and a custom-minutes option.
    await tester.tap(find.text('Song a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bedtime_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('Custom minutes…'), findsOneWidget);

    await tester.tap(find.text('Custom minutes…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '25');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(controller.hasSleepTimer, isTrue);
    expect(controller.sleepTimerEndsAt, DateTime(2025, 1, 1, 12, 25, 0));

    await controller.stopAndClear();
    await tester.pumpAndSettle();
    // The controller is app-scoped (owned by main, not the widget), so the
    // test that created it must dispose it to stop the sleep-timer ticker.
    controller.dispose();
  });

  testWidgets('playSongList sets context name for playback',
      (tester) async {
    final engine = FakeAudioEngine();
    final controller = MusicPlayerController(engine: engine);
    expect(controller.playbackContextName, isNull);

    await controller.playSongList(
      [_song('a', path: '/tmp/a.m4a')],
      contextName: 'Workout',
    );
    await tester.pumpAndSettle();
    expect(controller.playbackContextName, 'Workout');

    await controller.stopAndClear();
    expect(controller.playbackContextName, isNull);
  });

  testWidgets('Now Playing exposes the 10-second seek controls', (tester) async {
    final controller = MusicPlayerController(engine: FakeAudioEngine());
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Song a'));
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.byTooltip('Back 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Forward 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Previous'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);

    await controller.stopAndClear();
    await tester.pumpAndSettle();
  });

  testWidgets('Mini player stays visible on the playlist detail route',
      (tester) async {
    final controller = MusicPlayerController(engine: FakeAudioEngine());
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
    await tester.pumpAndSettle();

    // Navigate down into a detail page (All view) — an in-tab page that keeps
    // the app-level bottom navigation bar visible.
    await tester.tap(find.text('Playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    // The bottom navigation bar stays visible on the detail page.
    expect(find.byType(NavigationBar), findsOneWidget);

    // The global mini player still floats above the details.
    expect(find.text('Song a'), findsOneWidget);

    // Tapping it opens the full Now Playing view.
    await tester.tap(find.text('Song a'));
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsOneWidget);

    await controller.stopAndClear();
    await tester.pumpAndSettle();
  });

  testWidgets('SongTile surfaces the Continue resume hint', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SongTile(
          song: _song('a'),
          resumeLabel: 'Continue · 1:37',
        ),
      ),
    ));
    expect(find.text('Continue · 1:37'), findsOneWidget);
  });
}
