import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../player/audio_engine.dart';

/// Concrete [AudioEngine] backed by a single [AudioPlayer].
///
/// This intentionally keeps the factory-verified download-era guardrails:
/// - local playback refuses `http(s)` URLs,
/// - requires an absolute path,
/// - refuses missing / empty (0 byte) files.
class AudioService implements AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  final _stage = ValueNotifier<EngineStage>(EngineStage.idle);
  final _duration = ValueNotifier<Duration>(Duration.zero);
  final _position = ValueNotifier<Duration>(Duration.zero);

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  AudioService() {
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
    _positionSub = _player.positionStream.listen(
      (p) => _position.value = p,
    );
    _durationSub = _player.durationStream.listen(
      (d) => _duration.value = d ?? Duration.zero,
    );
  }

  void _onPlayerState(PlayerState state) {
    if (state.processingState == ProcessingState.completed) {
      _stage.value = EngineStage.completed;
    } else if (state.playing) {
      _stage.value = EngineStage.playing;
    } else if (state.processingState == ProcessingState.loading ||
        state.processingState == ProcessingState.buffering) {
      _stage.value = EngineStage.loading;
    } else {
      _stage.value = EngineStage.paused;
    }
  }

  @override
  ValueListenable<EngineStage> get stage => _stage;

  @override
  ValueListenable<Duration> get duration => _duration;

  @override
  ValueListenable<Duration> get position => _position;

  @override
  bool get hasLoadedSource => _player.audioSource != null;

  @override
  Future<void> loadRemote(String url) async {
    debugPrint('[AudioService] playStream -> $url');
    _stage.value = EngineStage.loading;
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(url)),
    );
    await _player.play();
  }

  @override
  Future<void> loadLocal(String filePath) async {
    debugPrint('[AudioService] playLocal called with: $filePath');

    final uri = Uri.tryParse(filePath);
    final scheme = uri?.scheme;
    if (scheme == 'http' || scheme == 'https') {
      throw AudioEngineException(
        'Refusing to play a remote URL as a local file: $filePath',
      );
    }

    // Device-collection tracks are addressed by a MediaStore content URI
    // (scoped storage). Play them through an audio source URI.
    if (scheme == 'content') {
      debugPrint('[AudioService] playing content URI: $filePath');
      _stage.value = EngineStage.loading;
      await _player.setAudioSource(AudioSource.uri(uri!));
      await _player.play();
      return;
    }

    if (!File(filePath).isAbsolute) {
      throw const AudioEngineException(
        'localPath is not an absolute filesystem path',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw const AudioEngineException('File does not exist on disk');
    }

    final length = await file.length();
    if (length == 0) {
      throw const AudioEngineException('File is empty (0 bytes)');
    }

    debugPrint('[AudioService] playing local file: $filePath '
        '($length bytes) via setFilePath');
    _stage.value = EngineStage.loading;
    await _player.setFilePath(filePath);
    await _player.play();
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    _position.dispose();
    _duration.dispose();
    _stage.dispose();
    await _player.dispose();
  }
}