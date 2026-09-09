import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/audio_service.dart' show AudioService;
import 'audio_engine.dart';
import 'player_queue.dart';

enum RepeatStyle { off, all, one }

/// Single app-wide playback controller. Owns the one [AudioEngine] used for
/// both preview streams and local files, plus the [PlayerQueue] state.
class MusicPlayerController extends ChangeNotifier {
  MusicPlayerController({
    AudioEngine? engine,
    this.streamUrlResolver,
    PlayerQueue? queue,
  })  : engine = engine ?? AudioService(),
        queue = queue ?? PlayerQueue();

  final AudioEngine engine;
  final PlayerQueue queue;

  /// Resolves a preview stream URL for a song id when playing previews.
  final Future<String?> Function(String songId)? streamUrlResolver;

  RepeatStyle repeatMode = RepeatStyle.off;
  final Set<String> favorites = {};

  /// Non-recoverable error shown to the user (kept friendly, never raw).
  String? lastError;

  bool get hasCurrentSong => queue.currentEntry != null;

  Song? get currentSong => queue.currentSong;

  PlaybackSource? get currentSource => queue.currentEntry?.source;

  bool get isPlaying => engine.stage.value == EngineStage.playing;

  EngineStage get stage => engine.stage.value;

  /// Position/duration exposed as ValueNotifiers so UI can subscribe cheaply.
  final _position = ValueNotifier<Duration>(Duration.zero);
  final _duration = ValueNotifier<Duration>(Duration.zero);

  ValueListenable<Duration> get positionNotifier => _position;

  ValueListenable<Duration> get durationNotifier => _duration;

  bool _disposed = false;

  /// Whether this controller is the one owned by the widget layer (it is the
  /// app singleton per session).
  void init() {
    engine.stage.addListener(_onEngineStageChanged);
    engine.position.addListener(_onPositionChanged);
    engine.duration.addListener(_onDurationChanged);
  }

  void _onEngineStageChanged() {
    _onEngineStage(engine.stage.value);
    notifyListeners();
  }

  void _onPositionChanged() {
    _position.value = engine.position.value;
  }

  void _onDurationChanged() {
    _duration.value = engine.duration.value;
  }

  void _onEngineStage(EngineStage stage) {
    if (stage == EngineStage.completed) {
      _autoAdvance();
    } else if (stage == EngineStage.error) {
      lastError = 'Playback error';
      notifyListeners();
    }
  }

  void _autoAdvance() {
    switch (repeatMode) {
      case RepeatStyle.one:
        _replayCurrent();
        break;
      case RepeatStyle.all:
        final next = queue.peekNext(wrapAtEnd: true);
        if (next != null) {
          queue.advance();
          _playCurrentEntry();
        }
        break;
      case RepeatStyle.off:
        final next = queue.peekNext(wrapAtEnd: false);
        if (next != null) {
          queue.advance();
          _playCurrentEntry();
        } else {
          _handleQueueEnd();
        }
    }
  }

  Future<void> _replayCurrent() async {
    await engine.seekTo(Duration.zero);
    await engine.play();
  }

  /// Queue ended with repeat off: park the player but keep the mini-player
  /// showing the finished track (UI can tap to replay).
  Future<void> _handleQueueEnd() async {
    await engine.pause();
    await engine.seekTo(Duration.zero);
  }

  Future<void> playLocal(Song song) async {
    _resetError();
    queue.insertAndPlay(QueueEntry(song: song, source: PlaybackSource.local));
    notifyListeners();
    try {
      await engine.loadLocal(song.localPath!);
    } catch (e) {
      _playbackFailed(song, e);
    }
  }

  Future<void> playLocalList(List<Song> songs, {int index = 0}) async {
    _resetError();
    final entries = songs
        .map((s) => QueueEntry(song: s, source: PlaybackSource.local))
        .toList();
    if (entries.isEmpty) {
      return;
    }
    queue.resetForPlayback(entries, playIndex: index);
    notifyListeners();
    await _playCurrentEntry();
  }

  Future<void> playPreview(Song song) async {
    _resetError();
    if (streamUrlResolver == null) {
      lastError = 'Preview unavailable';
      notifyListeners();
      return;
    }
    queue.insertAndPlay(QueueEntry(song: song, source: PlaybackSource.preview));
    notifyListeners();
    try {
      final url = await streamUrlResolver!(song.id);
      if (url == null) {
        queue.removeSong(song.id);
        lastError = 'No stream found for ${song.title}';
        notifyListeners();
        return;
      }
      await engine.loadRemote(url);
    } catch (e) {
      _playbackFailed(song, e);
    }
  }

  Future<void> _playCurrentEntry() async {
    final entry = queue.currentEntry;
    if (entry == null) {
      return;
    }
    try {
      if (entry.source == PlaybackSource.local && entry.song.localPath != null) {
        await engine.loadLocal(entry.song.localPath!);
      } else {
        final url = await streamUrlResolver?.call(entry.song.id);
        if (url == null) {
          queue.removeSong(entry.song.id);
          lastError = 'No stream found for ${entry.song.title}';
          notifyListeners();
          return;
        }
        await engine.loadRemote(url);
      }
    } catch (e) {
      _playbackFailed(entry.song, e);
    }
  }

  void _playbackFailed(Song song, Object error) {
    debugPrint('[MusicPlayerController] play failed for ${song.title}: $error');
    lastError = _friendlyError(error);
    queue.removeSong(song.id);
    notifyListeners();
    // Engine might be stuck in loading; force it idle so the mini-player hides.
    engine.stop();
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('File does not exist')) {
      return 'Local file is missing on disk';
    }
    if (msg.contains('empty')) {
      return 'Local file is empty (0 bytes)';
    }
    return 'Could not play this track';
  }

  Future<void> togglePause() async {
    if (!hasCurrentSong) {
      return;
    }
    if (isPlaying) {
      await engine.pause();
    } else {
      await engine.play();
    }
    notifyListeners();
  }

  Future<void> next() async {
    final nextEntry = queue.peekNext(wrapAtEnd: repeatMode == RepeatStyle.all);
    if (nextEntry == null) {
      await _handleQueueEnd();
      return;
    }
    queue.advance();
    await _playCurrentEntry();
  }

  Future<void> previous() async {
    if (_position.value > const Duration(seconds: 3)) {
      await engine.seekTo(Duration.zero);
      return;
    }
    final previousEntry = queue.peekPrevious();
    if (previousEntry != null) {
      final idx = queue.activeOrder.indexWhere((e) =>
          e.song.id == previousEntry.song.id && e.source == previousEntry.source);
      if (idx >= 0) {
        queue.goToActiveIndex(idx);
        await _playCurrentEntry();
      }
    }
  }

  Future<void> seekTo(Duration position) async {
    await engine.seekTo(position);
  }

  void toggleShuffle() {
    if (queue.isShuffleEnabled) {
      queue.disableShuffle();
    } else {
      queue.enableShuffle();
    }
    debugPrint('[MusicPlayerController] shuffle=${queue.isShuffleEnabled}');
    notifyListeners();
  }

  RepeatStyle get repeat => repeatMode;

  void cycleRepeat() {
    repeatMode = RepeatStyle.values[(repeatMode.index + 1) % RepeatStyle.values.length];
    debugPrint('[MusicPlayerController] repeat=${repeatMode.name}');
    notifyListeners();
  }

  void toggleFavorite(String songId) {
    if (!favorites.remove(songId)) {
      favorites.add(songId);
    }
    notifyListeners();
  }

  bool isFavorite(String songId) => favorites.contains(songId);

  void addToQueue(Song song, {PlaybackSource source = PlaybackSource.local}) {
    queue.addToQueue(QueueEntry(song: song, source: source));
    notifyListeners();
  }

  Future<void> playAtActiveIndex(int index) async {
    queue.goToActiveIndex(index);
    await _playCurrentEntry();
  }

  Future<void> removeAtActiveIndex(int index) async {
    final current = queue.currentSong;
    final removed = queue.removeAtActiveIndex(index);
    if (removed == null) {
      return;
    }
    if (current?.id == removed.song.id) {
      if (queue.currentEntry != null) {
        await _playCurrentEntry();
      } else {
        await stopAndClear();
      }
    }
    notifyListeners();
  }

  void clearQueue() {
    queue.clearUpcoming();
    notifyListeners();
  }

  void clearEverything() {
    queue.removeAll();
    notifyListeners();
  }

  /// Called when a song is deleted from the playlist/library. Stops playback
  /// if it was current. ([PersistedDownloadManager] removes from DB + disk.)
  Future<void> handleSongDeleted(String songId) async {
    final wasCurrent = queue.currentSong?.id == songId;
    if (wasCurrent) {
      queue.removeSong(songId);
      await stopAndClear();
      return;
    }
    queue.removeSong(songId);
    notifyListeners();
  }

  Future<void> stopAndClear() async {
    await engine.stop();
    queue.removeAll();
    _position.value = Duration.zero;
    _duration.value = Duration.zero;
    lastError = null;
    notifyListeners();
  }

  void _resetError() {
    if (lastError != null) {
      lastError = null;
    }
  }

  /// Builds a restored baseline from persisted settings (shuffle + repeat).
  void restoreSettings({required bool shuffle, required RepeatStyle repeat}) {
    repeatMode = repeat;
    if (shuffle != queue.isShuffleEnabled) {
      if (shuffle) {
        queue.enableShuffle();
      } else {
        queue.disableShuffle();
      }
    }
    notifyListeners();
  }

  ({bool shuffle, RepeatStyle repeat}) exportSettings() =>
      (shuffle: queue.isShuffleEnabled, repeat: repeatMode);

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    engine.stage.removeListener(_onEngineStageChanged);
    engine.position.removeListener(_onPositionChanged);
    engine.duration.removeListener(_onDurationChanged);
    _position.dispose();
    _duration.dispose();
    super.dispose();
  }

  bool get isDisposed => _disposed;
}