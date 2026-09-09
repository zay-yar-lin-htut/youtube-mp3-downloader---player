import 'package:flutter/foundation.dart';

/// Lifecycle stage of an [AudioEngine].
enum EngineStage { idle, loading, playing, paused, completed, error }

/// Wrapper for a negative engine result.
@immutable
class AudioEngineException implements Exception {
  const AudioEngineException(this.message);

  final String message;

  @override
  String toString() => 'AudioEngineException: $message';
}

/// Thin seam over the real audio backend (just_audio) so the player logic can
/// run in pure Dart widget tests without platform channels.
///
/// The app uses exactly ONE engine instance for preview streams and local
/// files alike — that is the whole point of the shared player.
abstract class AudioEngine {
  /// Streams the coarse playback stage. Emits initial [EngineStage.idle].
  ValueListenable<EngineStage> get stage;

  /// Streams current position while playing (self-advancing).
  ValueListenable<Duration> get position;

  /// Streams the total duration once a source is loaded.
  ValueListenable<Duration> get duration;

  bool get hasLoadedSource;

  /// Loads + plays a remote media source (e.g. a signed VISIONOS stream URL).
  Future<void> loadRemote(String url);

  /// Loads + plays a local media file at [filePath].
  Future<void> loadLocal(String filePath);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seekTo(Duration position);

  Future<void> dispose();
}