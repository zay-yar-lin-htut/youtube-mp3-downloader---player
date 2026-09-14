import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'audio_engine.dart';
import 'music_player_controller.dart';
import 'time_format.dart';

/// Bridges the app's single shared [MusicPlayerController] to the platform's
/// media session: the media notification, lock-screen controls, headset
/// buttons and Bluetooth/car commands all arrive here as standard callbacks,
/// which are forwarded to the existing controller (and its one engine). No
/// second playback system is introduced.
///
/// A singleton so the app can obtain the exact instance created by
/// [AudioService.init] in `main()` and attach the controller to it. The class
/// is plain-Dart on the Dart side, so it is safe to construct headlessly in
/// tests; only [AudioService.init] talks to the platform.
class MediaSessionHandler extends BaseAudioHandler with SeekHandler {
  MediaSessionHandler();

  static MediaSessionHandler? _instance;

  /// The one handler the platform media session talks to.
  static MediaSessionHandler get instance => _instance ??= MediaSessionHandler();

  MusicPlayerController? _controller;
  String? _publishedSongId;
  DateTime? _lastPositionPublish;

  /// How often a running position is mirrored to the media session. The
  /// platform projects the position between updates from the playing state.
  static const _positionPublishMinInterval = Duration(milliseconds: 500);

  bool get isAttached => _controller != null;

  /// Starts mirroring [controller] to the media session. Replaces any
  /// previously attached controller and immediately publishes its state.
  void attach(MusicPlayerController controller) {
    if (identical(_controller, controller)) {
      return;
    }
    detach();
    _controller = controller;
    controller.addListener(_onControllerChanged);
    controller.positionNotifier.addListener(_onPositionChanged);
    controller.durationNotifier.addListener(_onDurationChanged);
    _publishedSongId = null;
    _onControllerChanged();
  }

  /// Stops mirroring the controller and leaves the media session idle.
  void detach() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    controller.removeListener(_onControllerChanged);
    controller.positionNotifier.removeListener(_onPositionChanged);
    controller.durationNotifier.removeListener(_onDurationChanged);
    _controller = null;
    _publishedSongId = null;
    mediaItem.add(null);
    _publishIdle();
  }

  void _onControllerChanged() {
    final controller = _controller;
    final song = controller?.currentSong;
    if (song == null) {
      _publishedSongId = null;
      mediaItem.add(null);
      _publishIdle();
      return;
    }
    if (_publishedSongId != song.id) {
      _publishedSongId = song.id;
      mediaItem.add(_mediaItemFor(song));
    }
    _publishState(controller!);
  }

  void _onPositionChanged() {
    final controller = _controller;
    final now = DateTime.now();
    if (_lastPositionPublish != null &&
        now.difference(_lastPositionPublish!) < _positionPublishMinInterval) {
      return;
    }
    _lastPositionPublish = now;
    _publishState(controller);
  }

  void _onDurationChanged() {
    final controller = _controller;
    final song = controller?.currentSong;
    if (song == null) {
      return;
    }
    mediaItem.add(_mediaItemFor(song));
  }

  MediaItem _mediaItemFor(Song song) =>
      mediaItemFor(song, _controller?.durationNotifier.value ?? Duration.zero);

  /// Maps a [Song] to the [MediaItem] shown on the platform media session,
  /// preferring the loaded source duration when available and falling back to
  /// the persisted clock string so the seek bar exists before streaming loads.
  @visibleForTesting
  MediaItem mediaItemFor(Song song, Duration loadedDuration) {
    final duration = loadedDuration > Duration.zero
        ? loadedDuration
        : parseClockDuration(song.duration);
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.author,
      duration: duration > Duration.zero ? duration : null,
      artUri: _thumbnailUri(song.thumbnailUrl),
    );
  }

  Uri? _thumbnailUri(String thumbnailUrl) {
    if (thumbnailUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(thumbnailUrl);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    return uri;
  }

  void _publishIdle() {
    _lastPositionPublish = null;
    playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
      systemActions: const {MediaAction.seek},
    ));
  }

  void _publishState(MusicPlayerController? controller) {
    final song = controller?.currentSong;
    if (controller == null || song == null) {
      _publishIdle();
      return;
    }
    final playing = controller.isPlaying;
    final buffering = controller.stage == EngineStage.loading;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      systemActions: const {MediaAction.seek},
      processingState: buffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: playing,
      updatePosition: controller.positionNotifier.value,
    ));
  }

  // --- System command forwarding (notification / lock screen / Bluetooth) ---

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller == null || !controller.hasCurrentSong || controller.isPlaying) {
      return;
    }
    await controller.togglePause();
  }

  @override
  Future<void> pause() async {
    final controller = _controller;
    if (controller == null || !controller.isPlaying) {
      return;
    }
    await controller.togglePause();
  }

  @override
  Future<void> skipToPrevious() async {
    await _controller?.previous();
  }

  @override
  Future<void> skipToNext() async {
    await _controller?.next();
  }

  @override
  Future<void> seek(Duration position) async {
    await _controller?.seekTo(position);
  }

  @override
  Future<void> stop() async {
    await _controller?.stopAndClear();
  }
}