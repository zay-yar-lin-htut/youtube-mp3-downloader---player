import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_local_music/models/song.dart';
import 'package:yt_local_music/player/audio_engine.dart';
import 'package:yt_local_music/player/media_session_handler.dart';
import 'package:yt_local_music/player/music_player_controller.dart';
import 'package:yt_local_music/player/time_format.dart';

import 'fakes/fake_audio_engine.dart';

Song _song(String id,
        {String duration = '3:21', String thumb = ''}) =>
    Song(
      id: id,
      title: 'Title $id',
      author: 'Artist $id',
      duration: duration,
      thumbnailUrl: thumb.isEmpty ? '' : thumb,
      localPath: '/tmp/$id.m4a',
    );

void main() {
  group('parseClockDuration', () {
    test('parses m:ss and h:mm:ss clock strings', () {
      expect(parseClockDuration('3:21'), const Duration(seconds: 201));
      expect(parseClockDuration('0:05'), const Duration(seconds: 5));
      expect(parseClockDuration('1:02:33'),
          const Duration(hours: 1, minutes: 2, seconds: 33));
      expect(parseClockDuration('12'), Duration.zero);
      expect(parseClockDuration('abc'), Duration.zero);
      expect(parseClockDuration(''), Duration.zero);
      expect(parseClockDuration('1:2:3:4'), Duration.zero);
    });
  });

  group('MediaSessionHandler metadata mirroring', () {
    late MediaSessionHandler handler;
    late MusicPlayerController controller;
    late FakeAudioEngine engine;

    setUp(() {
      handler = MediaSessionHandler();
      engine = FakeAudioEngine();
      controller = MusicPlayerController(engine: engine);
      controller.init();
      handler.attach(controller);
    });

    tearDown(() {
      handler.detach();
      controller.dispose();
    });

    test('publishes a media item with full metadata when a song starts',
        () async {
      await controller
          .playLocal(_song('abc', thumb: 'https://i.ytimg.com/abc.jpg'));

      expect(handler.mediaItem.value?.id, 'abc');
      expect(handler.mediaItem.value?.title, 'Title abc');
      expect(handler.mediaItem.value?.artist, 'Artist abc');
      // Duration comes from the loaded source (fake engine = 210s).
      expect(handler.mediaItem.value?.duration,
          const Duration(seconds: 210));
      expect(handler.mediaItem.value?.artUri?.toString(),
          'https://i.ytimg.com/abc.jpg');

      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.controls,
          contains(MediaControl.pause));
      expect(handler.playbackState.value.androidCompactActionIndices,
          const [0, 1, 2]);
    });

    test('mediaItemFor prefers loaded duration and falls back to the clock '
        'string; omits artwork when none is available', () {
      expect(
        handler.mediaItemFor(_song('s', duration: '4:56'), Duration.zero)
            .duration,
        const Duration(seconds: 296),
      );
      expect(
        handler
            .mediaItemFor(_song('s', duration: '4:56'),
                const Duration(seconds: 210))
            .duration,
        const Duration(seconds: 210),
      );
      expect(
        handler.mediaItemFor(_song('s'), Duration.zero).artUri,
        isNull,
      );
      expect(
        handler
            .mediaItemFor(_song('s', thumb: 'https://i.ytimg.com/abc.jpg'),
                Duration.zero)
            .artUri
            ?.toString(),
        'https://i.ytimg.com/abc.jpg',
      );
    });

    test('updates the media item when playback advances to the next song',
        () async {
      await controller.playLocalList([_song('a'), _song('b')], index: 0);
      expect(handler.mediaItem.value?.id, 'a');

      await controller.next();
      expect(handler.mediaItem.value?.id, 'b');

      engine.complete();
    });

    test('clears the media item and goes idle when playback stops', () async {
      await controller.playLocal(_song('abc'));
      await handler.stop();

      expect(controller.currentSong, isNull);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
      expect(handler.playbackState.value.playing, isFalse);
    });

    test('detach leaves the session idle and untracked', () async {
      await controller.playLocal(_song('abc'));
      handler.detach();

      expect(handler.isAttached, isFalse);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
    });
  });

  group('MediaSessionHandler command forwarding', () {
    late MediaSessionHandler handler;
    late MusicPlayerController controller;
    late FakeAudioEngine engine;

    setUp(() {
      handler = MediaSessionHandler();
      engine = FakeAudioEngine();
      controller = MusicPlayerController(engine: engine);
      controller.init();
      handler.attach(controller);
    });

    tearDown(() {
      handler.detach();
      controller.dispose();
    });

    test('play/pause commands from the system toggle the shared controller',
        () async {
      await controller.playLocal(_song('abc'));
      expect(handler.playbackState.value.playing, isTrue);

      await handler.pause();
      expect(engine.currentStage, EngineStage.paused);
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls,
          contains(MediaControl.play));

      await handler.play();
      expect(engine.isPlaying, isTrue);
      expect(handler.playbackState.value.playing, isTrue);
    });

    test('play is a no-op when nothing is loaded or already playing', () async {
      await handler.play();
      expect(controller.currentSong, isNull);
      expect(handler.playbackState.value.playing, isFalse);

      await controller.playLocal(_song('abc'));
      await handler.play(); // already playing -> must not toggle to pause
      expect(engine.isPlaying, isTrue);
    });

    test('skipToNext and skipToPrevious drive the shared queue', () async {
      await controller.playLocalList([_song('a'), _song('b')], index: 0);
      expect(handler.mediaItem.value?.id, 'a');

      await handler.skipToNext();
      expect(controller.currentSong?.id, 'b');
      expect(handler.mediaItem.value?.id, 'b');

      await handler.skipToPrevious();
      expect(controller.currentSong?.id, 'a');
      expect(handler.mediaItem.value?.id, 'a');
    });

    test('seek forwards to the engine and mirrors the position', () async {
      await controller.playLocal(_song('abc'));
      await handler.seek(const Duration(seconds: 90));

      expect(engine.position.value, const Duration(seconds: 90));
      expect(handler.playbackState.value.updatePosition,
          const Duration(seconds: 90));
    });

    test('a swipe-away notification maps to stop and clears the session',
        () async {
      await controller.playLocalList([_song('a'), _song('b')], index: 0);
      // audio_service funnels onNotificationDeleted into stop(); verify it
      // maps to stopAndClear and drops the whole queue.
      await handler.onNotificationDeleted();

      expect(controller.hasCurrentSong, isFalse);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
    });
  });
}
