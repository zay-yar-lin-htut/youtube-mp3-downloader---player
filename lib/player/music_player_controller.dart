import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/audio_service.dart' show AudioService;
import '../services/resume_store.dart';
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
    DateTime Function()? clock,
    this.resumeStore,
  })  : engine = engine ?? AudioService(),
        queue = queue ?? PlayerQueue(),
        _clock = clock ?? DateTime.now;

  final AudioEngine engine;
  final PlayerQueue queue;
  final DateTime Function() _clock;

  /// Optional per-song resume store. When null, resume listening is disabled
  /// (so pure-Dart tests never touch the database). Production wires the real
  /// [DatabaseResumeStore] in main.dart.
  final ResumeStore? resumeStore;

  /// Resolves a preview stream URL for a song id when playing previews.
  final Future<String?> Function(String songId)? streamUrlResolver;

  RepeatStyle repeatMode = RepeatStyle.off;
  final Set<String> favorites = {};

  /// Where the current playback context came from (e.g. a playlist name or a
  /// system view like 'On device'). Shown as "From: X" in Now Playing and set
  /// whenever a visible list starts playback.
  String? playbackContextName;

  /// Non-recoverable error shown to the user (kept friendly, never raw).
  String? lastError;

  /// Id of the preview currently resolving/loading, if any. Only one preview
  /// may be active at a time; starting a new one invalidates the previous.
  String? _previewLoadingSongId;
  int _previewGeneration = 0;

  String? get previewLoadingSongId => _previewLoadingSongId;

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

  /// How often the running position is flushed while playing. Pause/stop/song
  /// changes always checkpoint immediately regardless of this interval.
  static const Duration resumeSaveInterval = Duration(seconds: 5);

  /// Absolute position of the last persisted resume point, used to throttle
  /// periodic saves. Null once nothing is saved yet for the active track.
  Duration? _lastPersistedPosition;

  /// In-memory mirror of saved resume positions (songId -> position). Warmly
  /// loaded at startup and updated as positions are saved/cleared so the UI
  /// can show "Continue · 1:37" hints without extra queries.
  final Map<String, Duration> resumePositions = {};

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
    _maybePersistResume();
  }

  void _onDurationChanged() {
    _duration.value = engine.duration.value;
  }

  void _onEngineStage(EngineStage stage) {
    if (stage == EngineStage.completed) {
      final finishedId = queue.currentSong?.id;
      _autoAdvance();
      // A song that finished naturally has no resume point anymore: replaying
      // it starts from the top.
      if (finishedId != null) {
        _clearResume(finishedId);
        _lastPersistedPosition = null;
      }
    } else if (stage == EngineStage.error) {
      lastError = 'Playback error';
      notifyListeners();
    }
  }

  /// Throttled periodic save of the running position (at most every
  /// [resumeSaveInterval]) so resume points survive a crash or a kill.
  void _maybePersistResume() {
    final song = queue.currentSong;
    final store = resumeStore;
    if (song == null || store == null) {
      return;
    }
    final pos = _position.value;
    if (pos <= Duration.zero) {
      return;
    }
    final last = _lastPersistedPosition;
    if (last != null && pos - last < resumeSaveInterval) {
      return;
    }
    _lastPersistedPosition = pos;
    resumePositions[song.id] = pos;
    unawaited(store.save(song.id, pos));
  }

  /// Immediate save of the current position (pause, stop, song change).
  Future<void> _checkpointResume() async {
    final song = queue.currentSong;
    final store = resumeStore;
    if (song == null || store == null) {
      return;
    }
    final pos = _position.value;
    if (pos <= Duration.zero) {
      return;
    }
    resumePositions[song.id] = pos;
    await store.save(song.id, pos);
  }

  /// Saves a specific song's position without touching queue state. Used to
  /// capture the outgoing track before a queue replacement.
  Future<void> _persistSnapshot(Song song, Duration position) async {
    final store = resumeStore;
    if (store == null || position <= Duration.zero) {
      return;
    }
    resumePositions[song.id] = position;
    await store.save(song.id, position);
  }

  /// Drops a song's saved resume point (natural completion / deletion).
  void _clearResume(String songId) {
    resumePositions.remove(songId);
    final store = resumeStore;
    if (store == null) {
      return;
    }
    unawaited(store.clear(songId));
  }

  /// Restores a saved position after a song loads. A position at or beyond the
  /// source duration is treated as finished and cleared instead.
  Future<void> _restorePosition(Song song) async {
    final store = resumeStore;
    if (store == null) {
      return;
    }
    try {
      final saved = await store.load(song.id);
      if (saved == null || saved <= Duration.zero) {
        return;
      }
      final total = engine.duration.value;
      if (total > Duration.zero && saved >= total) {
        resumePositions.remove(song.id);
        await store.clear(song.id);
        return;
      }
      await engine.seekTo(saved);
      resumePositions[song.id] = saved;
      if (!_disposed) {
        _position.value = saved;
      }
    } catch (e) {
      debugPrint('[MusicPlayerController] could not restore position: $e');
    }
  }

  /// Warms the in-memory resume cache from the store (call once at startup).
  Future<void> warmResumePositions() async {
    final store = resumeStore;
    if (store == null) {
      return;
    }
    try {
      final all = await store.loadAll();
      resumePositions
        ..clear()
        ..addAll(all);
      notifyListeners();
    } catch (e) {
      debugPrint('[MusicPlayerController] could not warm resume positions: $e');
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

  /// Chooses the playback source for a song: downloaded file, device file/URI,
  /// or a YouTube preview stream (in that order of preference).
  static PlaybackSource sourceFor(Song song) {
    if (song.source == SongSource.device) {
      return PlaybackSource.device;
    }
    if (song.localPath != null) {
      return PlaybackSource.local;
    }
    return PlaybackSource.preview;
  }

  Future<void> playLocal(Song song) async {
    await _checkpointResume();
    _resetError();
    playbackContextName = null;
    queue.insertAndPlay(QueueEntry(song: song, source: PlaybackSource.local));
    notifyListeners();
    try {
      await engine.loadLocal(song.localPath!);
      await _restorePosition(song);
    } catch (e) {
      _playbackFailed(song, e);
    }
  }

  Future<void> playLocalList(List<Song> songs,
      {int index = 0, String? contextName}) async {
    await _checkpointResume();
    _resetError();
    playbackContextName = contextName;
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

  /// Plays a list of songs using each song's own source (download / device /
  /// preview), useful for the Playlist view.
  Future<void> playSongList(List<Song> songs,
      {int index = 0, String? contextName}) async {
    await _checkpointResume();
    playbackContextName = contextName;
    final entries = <QueueEntry>[];
    for (final song in songs) {
      entries.add(QueueEntry(song: song, source: sourceFor(song)));
    }
    if (entries.isEmpty) {
      return;
    }
    _resetError();
    queue.resetForPlayback(entries, playIndex: index);
    notifyListeners();
    await _playCurrentEntry();
  }

  Future<void> playPreview(Song song) async {
    // Snapshot the outgoing track synchronously: replacing the queue below is
    // atomic, and waiting on persistence here would race the generation guard.
    final outgoing = queue.currentSong;
    if (outgoing != null) {
      unawaited(_persistSnapshot(outgoing, _position.value));
    }
    _resetError();
    playbackContextName = null;
    final generation = ++_previewGeneration;
    _previewLoadingSongId = song.id;
    queue.insertAndPlay(QueueEntry(song: song, source: PlaybackSource.preview));
    notifyListeners();
    // Stop any previously-playing source so only the new preview can sound.
    // Starting preview B while A is still resolving cancels A via the
    // generation guard below — its future result is silently dropped.
    await engine.stop();
    if (generation != _previewGeneration) {
      return; // superseded before we even resolved the URL
    }
    if (streamUrlResolver == null) {
      lastError = 'Preview unavailable';
      _previewLoadingSongId = null;
      notifyListeners();
      return;
    }
    try {
      final url = await streamUrlResolver!(song.id);
      if (generation != _previewGeneration) {
        return; // stale result — a newer preview owns the player now
      }
      if (url == null) {
        queue.removeSong(song.id);
        _previewLoadingSongId = null;
        lastError = 'No stream found for ${song.title}';
        notifyListeners();
        return;
      }
      await engine.loadRemote(url);
      if (generation != _previewGeneration) {
        return;
      }
      await _restorePosition(song);
      _previewLoadingSongId = null;
      notifyListeners();
    } catch (e) {
      if (generation != _previewGeneration) {
        return;
      }
      _playbackFailed(song, e);
    }
  }

  Future<void> _playCurrentEntry() async {
    final entry = queue.currentEntry;
    if (entry == null) {
      return;
    }
    try {
      if (entry.song.localPath != null &&
          (entry.source == PlaybackSource.local ||
              entry.source == PlaybackSource.device)) {
        await engine.loadLocal(entry.song.localPath!);
        await _restorePosition(entry.song);
      } else {
        final url = await streamUrlResolver?.call(entry.song.id);
        if (url == null) {
          queue.removeSong(entry.song.id);
          lastError = 'No stream found for ${entry.song.title}';
          notifyListeners();
          return;
        }
        await engine.loadRemote(url);
        await _restorePosition(entry.song);
      }
    } catch (e) {
      _playbackFailed(entry.song, e);
    }
  }

  void _playbackFailed(Song song, Object error) {
    debugPrint('[MusicPlayerController] play failed for ${song.title}: $error');
    lastError = _friendlyError(error);
    if (_previewLoadingSongId == song.id) {
      _previewLoadingSongId = null;
    }
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
      await _checkpointResume();
      await engine.pause();
    } else {
      await engine.play();
    }
    notifyListeners();
  }

  Future<void> next() async {
    await _checkpointResume();
    final nextEntry = queue.peekNext(wrapAtEnd: repeatMode == RepeatStyle.all);
    if (nextEntry == null) {
      await _handleQueueEnd();
      return;
    }
    queue.advance();
    await _playCurrentEntry();
    notifyListeners();
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
        await _checkpointResume();
        queue.goToActiveIndex(idx);
        await _playCurrentEntry();
      }
    }
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    await engine.seekTo(position);
  }

  /// Rewinds by 10 seconds, clamped at the start of the track.
  Future<void> seekBack10() async {
    final target = _position.value - const Duration(seconds: 10);
    final clamped = target.isNegative ? Duration.zero : target;
    await engine.seekTo(clamped);
    if (!_disposed) {
      _position.value = clamped;
    }
  }

  /// Skips forward by 10 seconds, clamped at the track duration.
  Future<void> seekForward10() async {
    final total = _duration.value;
    final target = _position.value + const Duration(seconds: 10);
    final clamped = total > Duration.zero && target > total ? total : target;
    await engine.seekTo(clamped);
    if (!_disposed) {
      _position.value = clamped;
    }
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

  /// Propagates a song edit (rename) to the live queue so playback and the
  /// mini-player reflect the new title/path. Queue identity and memberships
  /// are untouched because the song id never changes.
  void updateSong(Song updated) {
    queue.updateSong(updated);
    notifyListeners();
  }

  /// --- Sleep timer ---------------------------------------------------------
  ///
  /// A single absolute end time owned by this app-scoped controller, so the
  /// timer survives navigation, tab switches and rebuilds. Expiry pauses
  /// playback (it never deletes anything).
  DateTime? _sleepTimerEndsAt;
  Timer? _sleepTicker;

  bool get hasSleepTimer => _sleepTimerEndsAt != null;

  DateTime? get sleepTimerEndsAt => _sleepTimerEndsAt;

  Duration? get sleepTimerRemaining {
    final end = _sleepTimerEndsAt;
    if (end == null) return null;
    final remaining = end.difference(_clock());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void startSleepTimer(Duration duration) {
    _sleepTimerEndsAt = _clock().add(duration);
    _sleepTicker?.cancel();
    _sleepTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkSleepTimer(),
    );
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimerEndsAt = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    notifyListeners();
  }

  Future<void> _checkSleepTimer() async {
    final end = _sleepTimerEndsAt;
    if (end == null) return;
    if (_clock().isBefore(end)) return;
    _sleepTimerEndsAt = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    await _checkpointResume();
    await engine.pause();
    notifyListeners();
  }

  @visibleForTesting
  Future<void> triggerSleepTimerCheck() => _checkSleepTimer();

  void clearEverything() {
    queue.removeAll();
    notifyListeners();
  }

  /// Called when a song is deleted from the playlist/library. Stops playback
  /// if it was current. ([PersistedDownloadManager] removes from DB + disk.)
  Future<void> handleSongDeleted(String songId) async {
    final wasCurrent = queue.currentSong?.id == songId;
    if (_previewLoadingSongId == songId) {
      _previewGeneration++;
      _previewLoadingSongId = null;
    }
    if (wasCurrent) {
      queue.removeSong(songId);
      await stopAndClear();
      // The song is gone from the library; its resume point must vanish too
      // even though stopAndClear just checkpointed it.
      _clearResume(songId);
      return;
    }
    queue.removeSong(songId);
    _clearResume(songId);
    notifyListeners();
  }

  Future<void> stopAndClear() async {
    _previewGeneration++; // invalidate any in-flight preview
    _previewLoadingSongId = null;
    playbackContextName = null;
    await _checkpointResume();
    await engine.stop();
    queue.removeAll();
    _position.value = Duration.zero;
    _duration.value = Duration.zero;
    _lastPersistedPosition = null;
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
    _sleepTicker?.cancel();
    _sleepTicker = null;
    engine.stage.removeListener(_onEngineStageChanged);
    engine.position.removeListener(_onPositionChanged);
    engine.duration.removeListener(_onDurationChanged);
    _position.dispose();
    _duration.dispose();
    super.dispose();
  }

  bool get isDisposed => _disposed;
}