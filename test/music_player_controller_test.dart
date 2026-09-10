import 'dart:async';
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

    test('stopAndClear empties everything', () async {
      await controller.playLocal(_song('a', path: '/a.m4a'));
      await controller.stopAndClear();
      expect(controller.hasCurrentSong, isFalse);
      expect(controller.stage, EngineStage.idle);
    });
  });

  group('MusicPlayerController sleep timer', () {
    test('start and cancel timer', () {
      controller.dispose();
      controller = MusicPlayerController(
        engine: FakeAudioEngine(),
        clock: () => DateTime(2025),
      );
      controller.init();
      addTearDown(controller.dispose);

      controller.startSleepTimer(const Duration(minutes: 30));
      expect(controller.hasSleepTimer, isTrue);
      expect(controller.sleepTimerEndsAt, DateTime(2025).add(const Duration(minutes: 30)));
      final remaining = controller.sleepTimerRemaining;
      expect(remaining, isNotNull);
      expect(remaining!.inMinutes, 30);

      controller.cancelSleepTimer();
      expect(controller.hasSleepTimer, isFalse);
      expect(controller.sleepTimerRemaining, isNull);
    });

    test('timer expiry pauses playback', () async {
      var now = DateTime(2025);
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        clock: () => now,
      );
      controller.init();
      addTearDown(controller.dispose);

      await controller.playLocal(_song('a', path: '/a.m4a'));
      expect(controller.isPlaying, isTrue);

      controller.startSleepTimer(const Duration(minutes: 5));
      // Simulate time passing.
      now = now.add(const Duration(minutes: 5));
      await controller.triggerSleepTimerCheck();
      expect(controller.isPlaying, isFalse);
      expect(controller.hasSleepTimer, isFalse);
    });
  });

  group('MusicPlayerController context', () {
    test('playSongList sets context name', () async {
      await controller.playSongList(
        [_song('a', path: '/a.m4a')],
        contextName: 'Workout',
      );
      expect(controller.playbackContextName, 'Workout');
    });

    test('playLocal clears context name', () async {
      controller.playbackContextName = 'Workout';
      await controller.playLocal(_song('a', path: '/a.m4a'));
      expect(controller.playbackContextName, isNull);
    });

    test('stopAndClear clears context name', () async {
      controller.playbackContextName = 'Workout';
      await controller.stopAndClear();
      expect(controller.playbackContextName, isNull);
    });

    test('updateSong propagates to current queue entry', () async {
      await controller.playLocal(_song('a', path: '/a.m4a'));
      expect(controller.currentSong!.title, 'Title a');

      controller.updateSong(_song('a', path: '/a_new.m4a'));
      expect(controller.currentSong!.title, 'Title a');
      expect(controller.currentSong!.localPath, '/a_new.m4a');
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

  group('MusicPlayerController preview switching', () {
    test('exposes a loading id while resolving and clears it after load',
        () async {
      final gate = Completer<String>();
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        streamUrlResolver: (_) => gate.future,
      );
      controller.init();

      final pending = controller.playPreview(_song('preview', path: null));
      expect(controller.previewLoadingSongId, 'preview');
      expect(controller.currentSong!.id, 'preview');

      gate.complete('https://stream/preview');
      await pending;
      expect(controller.previewLoadingSongId, isNull);
      expect(controller.currentSong!.id, 'preview');
      expect(engine.loadedSources.last, 'https://stream/preview');
    });

    test('starting a second preview supersedes the first while it resolves',
        () async {
      final gateA = Completer<String>();
      final gateB = Completer<String>();
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        streamUrlResolver: (id) => id == 'a' ? gateA.future : gateB.future,
      );
      controller.init();

      final previewA = controller.playPreview(_song('a'));
      expect(controller.previewLoadingSongId, 'a');
      final previewB = controller.playPreview(_song('b'));
      expect(controller.previewLoadingSongId, 'b');
      expect(controller.currentSong!.id, 'b');

      // The stale preview A resolves late — its stream must never be loaded.
      gateA.complete('https://stream/a');
      await previewA;
      expect(engine.loadedSources, isEmpty);
      expect(controller.currentSong!.id, 'b');
      expect(controller.previewLoadingSongId, 'b');

      gateB.complete('https://stream/b');
      await previewB;
      expect(controller.previewLoadingSongId, isNull);
      expect(controller.currentSong!.id, 'b');
      expect(engine.loadedSources, ['https://stream/b']);
    });

    test('stopAndClear invalidates an in-flight preview', () async {
      final gate = Completer<String>();
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        streamUrlResolver: (_) => gate.future,
      );
      controller.init();

      final pending = controller.playPreview(_song('a'));
      await controller.stopAndClear();
      expect(controller.hasCurrentSong, isFalse);

      gate.complete('https://stream/a');
      await pending;
      expect(controller.hasCurrentSong, isFalse);
      expect(engine.loadedSources, isEmpty);
      expect(controller.previewLoadingSongId, isNull);
    });

    test('handleSongDeleted invalidates an in-flight preview for that song',
        () async {
      final gate = Completer<String>();
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        streamUrlResolver: (_) => gate.future,
      );
      controller.init();

      final pending = controller.playPreview(_song('a'));
      expect(controller.previewLoadingSongId, 'a');
      await controller.handleSongDeleted('a');
      expect(controller.hasCurrentSong, isFalse);

      gate.complete('https://stream/a');
      await pending;
      expect(engine.loadedSources, isEmpty);
      expect(controller.previewLoadingSongId, isNull);
    });

    test('a failed preview clears the loading id so the row can be retried',
        () async {
      final gate = Completer<String>();
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        streamUrlResolver: (_) => gate.future,
      );
      controller.init();

      final pending = controller.playPreview(_song('bad'));
      expect(controller.previewLoadingSongId, 'bad');

      gate.completeError(StateError('unavailable'));
      await pending;
      expect(controller.currentSong, isNull);
      expect(controller.previewLoadingSongId, isNull);
    });
  });

  group('MusicPlayerController playSongList', () {
    test('routes a device song through the local engine with a device URI',
        () async {
      final deviceSong = Song(
        id: 'd_123',
        title: 'Device track',
        author: 'Album Artist',
        duration: '4:11',
        thumbnailUrl: '',
        localPath: 'content://media/external/audio/media/999',
        source: SongSource.device,
      );
      await controller.playSongList([deviceSong]);
      expect(controller.currentSong!.id, 'd_123');
      expect(controller.currentSource, PlaybackSource.device);
      expect(controller.isPlaying, isTrue);
      expect(engine.loadedSources.first,
          'file:content://media/external/audio/media/999');
    });

    test('routes downloaded and preview entries by their own sources', () async {
      controller.dispose();
      controller = MusicPlayerController(
        engine: engine,
        streamUrlResolver: (id) async => 'https://stream/$id',
      );
      controller.init();

      final downloaded = _song('dl', path: '/data/audio/dl.m4a');
      final device = Song(
        id: 'd_abc',
        title: 'Device track',
        author: 'Artist',
        duration: '2:00',
        thumbnailUrl: '',
        localPath: 'content://media/external/audio/media/7',
        source: SongSource.device,
      );
      final onlyYt = _song('yt'); // no local file -> preview

      await controller.playSongList([downloaded, device, onlyYt], index: 1);
      expect(controller.currentSong!.id, 'd_abc');
      expect(controller.currentSource, PlaybackSource.device);
      expect(engine.loadedSources.first,
          'file:content://media/external/audio/media/7');

      await controller.playSongList([downloaded, device, onlyYt], index: 2);
      expect(controller.currentSource, PlaybackSource.preview);
      expect(engine.loadedSources.last, 'https://stream/yt');
    });

    test('sourceFor picks device, then local, then preview', () {
      expect(
        MusicPlayerController.sourceFor(_song('a')), // no path
        PlaybackSource.preview,
      );
      expect(
        MusicPlayerController.sourceFor(_song('b', path: '/x/b.m4a')),
        PlaybackSource.local,
      );
      expect(
        MusicPlayerController.sourceFor(Song(
          id: 'd',
          title: 't',
          author: 'a',
          duration: '1:00',
          thumbnailUrl: '',
          localPath: 'content://media/external/audio/media/1',
          source: SongSource.device,
        )),
        PlaybackSource.device,
      );
    });
  });
}