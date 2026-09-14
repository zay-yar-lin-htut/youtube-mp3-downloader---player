import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/music_player_controller.dart';
import 'package:yt_local_music/screens/now_playing_screen.dart';
import 'package:yt_local_music/screens/playlist_screen.dart';
import 'package:yt_local_music/services/library_storage.dart';
import 'package:yt_local_music/services/playlist_repository.dart';

import 'fakes/fake_audio_engine.dart';
import 'fakes/fake_resume_store.dart';

Song _song(String id, {String? title}) => Song(
      id: id,
      title: title ?? 'Song $id',
      author: 'Artist',
      duration: '3:21',
      thumbnailUrl: '',
      localPath: '/tmp/$id.m4a',
      source: SongSource.device,
    );

class _FakeStorage implements LibraryStorage {
  _FakeStorage(this.songs);

  final List<Song> songs;

  @override
  Future<List<Song>> getPlaylist() async => List.of(songs);

  @override
  Future<void> insertSong(Song song) async {}

  @override
  Future<void> updateSong(Song song) async {}

  @override
  Future<void> deleteSong(String id) async {}
}

void main() {
  late FakeAudioEngine engine;
  late FakeResumeStore resumeStore;
  late MusicPlayerController player;
  late PlaylistRepository repo;

  setUp(() {
    engine = FakeAudioEngine();
    resumeStore = FakeResumeStore();
    player = MusicPlayerController(engine: engine, resumeStore: resumeStore);
    player.init();
    repo = PlaylistRepository(
      storage: _FakeStorage([_song('a'), _song('b'), _song('c')]),
      device: null,
    );
  });

  tearDown(() {
    player.dispose();
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistDetailScreen(
            playerController: player,
            repository: repo,
            systemView: PlaylistSystemView.all,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder playButton() => find.byTooltip('Play');
  Finder pauseButton() => find.byTooltip('Pause');

  group('PlaylistDetail navigation', () {
    testWidgets('renders the song rows', (tester) async {
      await pumpDetail(tester);
      expect(find.text('Song a'), findsOneWidget);
      expect(find.text('Song b'), findsOneWidget);
      expect(find.text('Song c'), findsOneWidget);
    });

    testWidgets('tapping the row body starts it and opens Now Playing', (
      tester,
    ) async {
      await pumpDetail(tester);

      await tester.tap(find.text('Song a'));
      await tester.pumpAndSettle();

      expect(find.text('Now Playing'), findsOneWidget);
      expect(player.currentSong?.id, 'a');
      expect(player.isPlaying, isTrue);
    });

    testWidgets('tapping a different song body switches playback, then opens '
        'Now Playing', (tester) async {
      await pumpDetail(tester);
      await player.playLocal(_song('a'));
      await tester.pumpAndSettle();
      expect(player.currentSong?.id, 'a');

      await tester.tap(find.text('Song b'));
      await tester.pumpAndSettle();

      expect(find.text('Now Playing'), findsOneWidget);
      expect(player.currentSong?.id, 'b');
    });

    testWidgets('tapping the row body of the current song only opens Now '
        'Playing without interrupting playback', (tester) async {
      await pumpDetail(tester);
      await player.playLocal(_song('a'));
      await tester.pumpAndSettle();
      expect(player.isPlaying, isTrue);

      await tester.tap(find.text('Song a'));
      await tester.pumpAndSettle();

      expect(find.text('Now Playing'), findsOneWidget);
      expect(player.currentSong?.id, 'a');
      expect(player.isPlaying, isTrue);
    });
  });

  group('PlaylistDetail play/pause button', () {
    testWidgets('current + playing shows Pause and tapping it pauses without '
        'navigating', (tester) async {
      await pumpDetail(tester);
      await player.playSongList(
        [_song('a'), _song('b'), _song('c')],
        contextName: 'All',
      );
      await tester.pumpAndSettle();

      expect(player.currentSong?.id, 'a');
      expect(player.isPlaying, isTrue);
      expect(pauseButton(), findsOneWidget);

      await tester.tap(pauseButton());
      await tester.pumpAndSettle();

      expect(player.isPlaying, isFalse);
      expect(player.currentSong?.id, 'a');
      expect(find.text('Now Playing'), findsNothing);
      expect(find.byType(NowPlayingScreen), findsNothing);
    });

    testWidgets('current + paused shows Play and tapping it resumes from the '
        'current position without restarting', (tester) async {
      await pumpDetail(tester);
      await player.playSongList(
        [_song('a'), _song('b')],
        contextName: 'All',
      );
      await tester.pumpAndSettle();

      await tester.tap(pauseButton());
      await tester.pumpAndSettle();
      expect(player.isPlaying, isFalse);

      // Move the caret to 1:40 while paused (as real playback would).
      await engine.seekTo(const Duration(seconds: 100));
      await tester.pumpAndSettle();

      await tester.tap(playButton().first);
      await tester.pumpAndSettle();

      expect(player.isPlaying, isTrue);
      expect(player.currentSong?.id, 'a');
      // Resumed from the actual position, not reset to zero.
      expect(engine.position.value, const Duration(seconds: 100));
      expect(find.text('Now Playing'), findsNothing);
    });

    testWidgets('a different song Play button selects and starts that song '
        'without navigating', (tester) async {
      await pumpDetail(tester);
      await player.playSongList(
        [_song('a'), _song('b'), _song('c')],
        contextName: 'All',
      );
      await tester.pumpAndSettle();
      expect(player.currentSong?.id, 'a');

      await tester.tap(playButton().first);
      await tester.pumpAndSettle();

      expect(player.currentSong?.id, 'b');
      expect(player.isPlaying, isTrue);
      expect(find.text('Now Playing'), findsNothing);
    });

    testWidgets('with no current song the Play button starts that song', (
      tester,
    ) async {
      await pumpDetail(tester);
      expect(player.hasCurrentSong, isFalse);

      await tester.tap(playButton().first);
      await tester.pumpAndSettle();

      expect(player.currentSong?.id, 'a');
      expect(player.isPlaying, isTrue);
      expect(find.text('Now Playing'), findsNothing);
    });
  });

  group('PlaylistDetail button state', () {
    testWidgets('icons follow the shared player state', (tester) async {
      await pumpDetail(tester);
      await player.playSongList(
        [_song('a'), _song('b')],
        contextName: 'All',
      );
      await tester.pumpAndSettle();

      // Current + playing -> Pause icon on 'a'; Play on 'b' and 'c'.
      expect(pauseButton(), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(playButton(), findsNWidgets(2));

      // Pause -> current shows Play again, shared state is the source of truth.
      await tester.tap(pauseButton());
      await tester.pumpAndSettle();
      expect(pauseButton(), findsNothing);
      expect(playButton(), findsNWidgets(3));
      expect(player.isPlaying, isFalse);
    });

    testWidgets('pausing and resuming does not change the saved resume '
        'position', (tester) async {
      await pumpDetail(tester);
      await player.playSongList([_song('a')], contextName: 'All');
      await tester.pumpAndSettle();

      // While playing, move to 1:15; the throttled save records it.
      await engine.seekTo(const Duration(seconds: 75));
      await tester.pumpAndSettle();
      expect(resumeStore.data['a'], const Duration(seconds: 75));

      await tester.tap(pauseButton());
      await tester.pumpAndSettle();
      expect(resumeStore.data['a'], const Duration(seconds: 75));

      await tester.tap(playButton().first);
      await tester.pumpAndSettle();
      expect(player.isPlaying, isTrue);
      expect(resumeStore.data['a'], const Duration(seconds: 75));
      expect(engine.position.value, const Duration(seconds: 75));
    });

    testWidgets('a naturally completed song loses its resume point and the '
        'row shows read-to-play', (tester) async {
      await pumpDetail(tester);
      await player.playSongList([_song('a')], contextName: 'All');
      await engine.seekTo(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(resumeStore.data['a'], isNotNull);

      engine.complete();
      await tester.pumpAndSettle();

      expect(resumeStore.data.containsKey('a'), isFalse);
      expect(player.currentSong?.id, 'a');
      expect(player.isPlaying, isFalse);
      // A finished track is no longer active-live: Play (not Pause) shown.
      expect(pauseButton(), findsNothing);
    });
  });
}