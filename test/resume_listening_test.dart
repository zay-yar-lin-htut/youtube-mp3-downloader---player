import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/music_player_controller.dart';
import 'fakes/fake_audio_engine.dart';
import 'fakes/fake_resume_store.dart';

Song _song(String id, {String? path}) => Song(
      id: id,
      title: 'Title $id',
      author: 'Author',
      duration: '3:30',
      thumbnailUrl: '',
      localPath: path,
    );

void main() {
  late FakeAudioEngine engine;
  late FakeResumeStore store;
  late MusicPlayerController controller;

  setUp(() {
    engine = FakeAudioEngine();
    store = FakeResumeStore();
    controller = MusicPlayerController(engine: engine, resumeStore: store);
    controller.init();
  });

  tearDown(() {
    controller.dispose();
  });

  group('resume listening: restore', () {
    test('replays from the saved position for the same song', () async {
      store.data['a'] = const Duration(seconds: 90);
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      expect(controller.positionNotifier.value, const Duration(seconds: 90));
    });

    test('restores mid-track positions through playSongList', () async {
      store.data['b'] = const Duration(seconds: 15);
      await controller.playSongList(
        [_song('a', path: '/tmp/a.m4a'), _song('b', path: '/tmp/b.m4a')],
        index: 1,
      );
      expect(controller.currentSong!.id, 'b');
      expect(controller.positionNotifier.value, const Duration(seconds: 15));
    });

    test('seeks to zero when the saved position reaches the end', () async {
      store.data['a'] = const Duration(seconds: 220); // fake duration is 210s
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      expect(controller.positionNotifier.value, Duration.zero);
      expect(store.data.containsKey('a'), isFalse);
    });
  });

  group('resume listening: clearing', () {
    test('clears the resume when a song finishes naturally', () async {
      await controller.playLocalList([
        _song('a', path: '/tmp/a.m4a'),
        _song('b', path: '/tmp/b.m4a'),
      ]);
      engine.complete(); // a finishes -> clears, auto-advances to b
      expect(controller.currentSong!.id, 'b');
      expect(store.data.containsKey('a'), isFalse);
    });

    test('clears the resume point when a song is deleted', () async {
      store.data['a'] = const Duration(seconds: 40);
      await controller.playSongList([
        _song('a', path: '/tmp/a.m4a'),
        _song('b', path: '/tmp/b.m4a'),
      ]);
      await controller.handleSongDeleted('b');
      expect(controller.currentSong!.id, 'a');
      expect(store.data.containsKey('b'), isFalse);
      expect(store.data['a'], const Duration(seconds: 40));
    });

    test('clears the current song resume when it is deleted', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      engine.seekTo(const Duration(seconds: 60));
      await controller.handleSongDeleted('a');
      expect(controller.hasCurrentSong, isFalse);
      expect(store.data.containsKey('a'), isFalse);
    });
  });

  group('resume listening: saving', () {
    test('pause checkpoints the current position', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      engine.seekTo(const Duration(seconds: 97));
      await controller.togglePause();
      expect(store.data['a'], const Duration(seconds: 97));
      expect(controller.resumePositions['a'], const Duration(seconds: 97));
    });

    test('playback checkpoints the previous song on next', () async {
      await controller.playLocalList([
        _song('a', path: '/tmp/a.m4a'),
        _song('b', path: '/tmp/b.m4a'),
      ]);
      engine.seekTo(const Duration(seconds: 32));
      await controller.next();
      expect(controller.currentSong!.id, 'b');
      expect(store.data['a'], const Duration(seconds: 32));
    });

    test('close player keeps the resume point for a later replay', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      engine.seekTo(const Duration(seconds: 120));
      await controller.stopAndClear();
      expect(controller.hasCurrentSong, isFalse);
      expect(store.data['a'], const Duration(seconds: 120));
    });

    test('periodically saves while playing', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      engine.seekTo(const Duration(seconds: 5));
      expect(store.data['a'], const Duration(seconds: 5));
      engine.seekTo(const Duration(seconds: 8)); // < 5s since last save
      expect(store.data['a'], const Duration(seconds: 5));
      engine.seekTo(const Duration(seconds: 11)); // crossed the interval
      expect(store.data['a'], const Duration(seconds: 11));
    });

    test('warmResumePositions caches every stored resume point', () async {
      store.data['a'] = const Duration(seconds: 60);
      store.data['b'] = const Duration(seconds: 17);
      await controller.warmResumePositions();
      expect(controller.resumePositions['a'], const Duration(seconds: 60));
      expect(controller.resumePositions['b'], const Duration(seconds: 17));
    });
  });

  group('10 second seek', () {
    test('seekBack10 clamps at the start of the track', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      engine.seekTo(const Duration(seconds: 5));
      await controller.seekBack10();
      expect(controller.positionNotifier.value, Duration.zero);
    });

    test('seekBack10 rewinds by exactly ten seconds', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      engine.seekTo(const Duration(seconds: 90));
      await controller.seekBack10();
      expect(controller.positionNotifier.value, const Duration(seconds: 80));
    });

    test('seekForward10 clamps at the track duration', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      engine.seekTo(const Duration(seconds: 207)); // duration is 210s
      await controller.seekForward10();
      expect(controller.positionNotifier.value, const Duration(seconds: 210));
    });

    test('seekForward10 skips exactly ten seconds', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      engine.seekTo(const Duration(seconds: 60));
      await controller.seekForward10();
      expect(controller.positionNotifier.value, const Duration(seconds: 70));
    });
  });
}