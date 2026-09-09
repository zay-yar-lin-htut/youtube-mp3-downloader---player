import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/audio_engine.dart';
import 'package:yt_local_music/player/music_player_controller.dart';
import 'package:yt_local_music/player/player_queue.dart';
import 'fakes/fake_audio_engine.dart';

Song _song(String id, {String? path}) => Song(
      id: id,
      title: 'Title $id',
      author: 'Author',
      duration: '3:00',
      thumbnailUrl: '',
      localPath: path,
    );

void main() {
  late FakeAudioEngine engine;
  late MusicPlayerController controller;

  setUp(() {
    engine = FakeAudioEngine();
    controller = MusicPlayerController(engine: engine);
    controller.init();
  });

  tearDown(() {
    controller.dispose();
  });

  group('MusicPlayerController playback', () {
    test('playLocal loads the local file and plays', () async {
      await controller.playLocal(_song('a', path: '/tmp/a.m4a'));
      expect(controller.currentSong!.id, 'a');
      expect(controller.currentSource, PlaybackSource.local);
      expect(controller.isPlaying, isTrue);
      expect(engine.loadedSources.first, 'file:/tmp/a.m4a');
    });

    test('playPreview resolves URL through resolver and loads remotely', () async {
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        streamUrlResolver: (id) async => 'https://stream/$id',
      );
      controller.init();

      await controller.playPreview(_song('a'));
      expect(controller.currentSong!.id, 'a');
      expect(controller.currentSource, PlaybackSource.preview);
      expect(engine.loadedSources.first, 'https://stream/a');
    });

    test('playPreview surfaces friendly message when resolver returns null', () async {
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        streamUrlResolver: (id) async => null,
      );
      controller.init();

      await controller.playPreview(_song('a'));
      expect(controller.lastError, 'No stream found for Title a');
      expect(controller.currentSong, isNull);
    });

    test('failed local load clears the song and reports friendly error', () async {
      engine.loadError = StateError('File does not exist');
      await controller.playLocal(_song('a', path: '/missing.m4a'));
      expect(controller.lastError, 'Local file is missing on disk');
      expect(controller.hasCurrentSong, isFalse);
      expect(engine.currentStage, EngineStage.idle);
    });

    test('togglePause toggles playback state', () async {
      await controller.playLocal(_song('a', path: '/a.m4a'));
      expect(controller.isPlaying, isTrue);
      await controller.togglePause();
      expect(controller.isPlaying, isFalse);
      await controller.togglePause();
      expect(controller.isPlaying, isTrue);
    });

    test('auto-advances to next on completed with repeat off', () async {
      controller.dispose();
      controller = MusicPlayerController(engine: engine);
      controller.init();
      final songs = [
        _song('a', path: '/a.m4a'),
        _song('b', path: '/b.m4a'),
      ];
      await controller.playLocalList(songs, index: 0);
      engine.complete();
      expect(controller.currentSong!.id, 'b');
      expect(controller.isPlaying, isTrue);
    });

    test('auto-advance stops at queue end when repeat off', () async {
      controller.dispose();
      controller = MusicPlayerController(engine: engine);
      controller.init();
      await controller.playLocalList([_song('a', path: '/a.m4a')]);
      engine.complete();
      expect(controller.currentSong!.id, 'a');
      expect(controller.isPlaying, isFalse);
    });

    test('repeat one replays current track', () async {
      controller.dispose();
      controller = MusicPlayerController(engine: engine);
      controller.init();
      await controller.playLocalList([_song('a', path: '/a.m4a')]);
      controller.cycleRepeat(); // all
      controller.cycleRepeat(); // one
      engine.seekTo(const Duration(seconds: 90));
      engine.complete();
      await Future<void>.delayed(Duration.zero); // flush async replay
      expect(controller.currentSong!.id, 'a');
      expect(controller.isPlaying, isTrue);
    });

    test('repeat all wraps to first track at end', () async {
      controller.dispose();
      controller = MusicPlayerController(engine: engine);
      controller.init();
      await controller.playLocalList([
        _song('a', path: '/a.m4a'),
        _song('b', path: '/b.m4a'),
      ]);
      controller.cycleRepeat(); // all
      engine.complete(); // -> b
      engine.complete(); // -> wraps to a
      expect(controller.currentSong!.id, 'a');
    });
  });

  group('MusicPlayerController queue', () {
    test('next and previous move through the playlist', () async {
      final songs = [
        _song('a', path: '/a.m4a'),
        _song('b', path: '/b.m4a'),
      ];
      await controller.playLocalList(songs);
      expect(controller.queue.length, 2);
      await controller.next();
      expect(controller.currentSong!.id, 'b');
      await controller.previous();
      expect(controller.currentSong!.id, 'a');
    });

    test('addToQueue appends and can be played', () async {
      await controller.playLocal(_song('a', path: '/a.m4a'));
      controller.addToQueue(_song('b', path: '/b.m4a'));
      expect(controller.queue.peekNext()!.song.id, 'b');
      await controller.playAtActiveIndex(1);
      expect(controller.currentSong!.id, 'b');
    });

    test('removeAtActiveIndex of current switches to next', () async {
      await controller.playLocalList([
        _song('a', path: '/a.m4a'),
        _song('b', path: '/b.m4a'),
      ]);
      await controller.removeAtActiveIndex(0);
      expect(controller.currentSong!.id, 'b');
      expect(controller.isPlaying, isTrue);
    });

    test('stopAndClear empties everything', () async {
      await controller.playLocal(_song('a', path: '/a.m4a'));
      await controller.stopAndClear();
      expect(controller.hasCurrentSong, isFalse);
      expect(controller.stage, EngineStage.idle);
    });
  });

  group('MusicPlayerController settings', () {
    test('shuffle toggle persists through export/restore', () {
      controller.toggleShuffle();
      expect(controller.queue.isShuffleEnabled, isTrue);
      final saved = controller.exportSettings();
      expect(saved.shuffle, isTrue);
      controller.restoreSettings(shuffle: false, repeat: RepeatStyle.off);
      expect(controller.queue.isShuffleEnabled, isFalse);
    });

    test('repeat cycling moves off -> all -> one', () {
      expect(controller.repeat, RepeatStyle.off);
      controller.cycleRepeat();
      expect(controller.repeat, RepeatStyle.all);
      controller.cycleRepeat();
      expect(controller.repeat, RepeatStyle.one);
      controller.cycleRepeat();
      expect(controller.repeat, RepeatStyle.off);
    });

    test('favorites are toggleable in-memory', () {
      expect(controller.isFavorite('a'), isFalse);
      controller.toggleFavorite('a');
      expect(controller.isFavorite('a'), isTrue);
      controller.toggleFavorite('a');
      expect(controller.isFavorite('a'), isFalse);
    });
  });

  group('MusicPlayerController delete flow', () {
    test('handleSongDeleted stops playback when current', () async {
      await controller.playLocal(_song('a', path: '/a.m4a'));
      await controller.handleSongDeleted('a');
      expect(controller.hasCurrentSong, isFalse);
      expect(controller.stage, EngineStage.idle);
    });

    test('handleSongDeleted removes non-current from queue only', () async {
      await controller.playLocalList([
        _song('a', path: '/a.m4a'),
        _song('b', path: '/b.m4a'),
      ]);
      await controller.handleSongDeleted('b');
      expect(controller.currentSong!.id, 'a');
      expect(controller.queue.length, 1);
    });
  });
}